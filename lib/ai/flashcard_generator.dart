import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

/// One AI-suggested card, not yet written to the database — the caller
/// decides which ones to keep.
class GeneratedCard {
  final String front;
  final String back;

  const GeneratedCard({required this.front, required this.back});
}

/// Thrown when the model's response couldn't be turned into cards — a bad
/// generation, not a plumbing failure, so callers should offer "try again"
/// rather than treating it like a network/model-load error.
class FlashcardGenerationException implements Exception {
  final String message;
  const FlashcardGenerationException(this.message);

  @override
  String toString() => message;
}

/// Generates flashcards from pasted study text. Abstracted so screens stay
/// testable with a fake — [OnDeviceFlashcardGenerator] drives a real on-device
/// model via platform channels flutter_test can't exercise (same reason
/// `MediaPicker`/`ReminderScheduler` are abstracted elsewhere in this app).
abstract class FlashcardGenerator {
  /// [onDownloadProgress] (0-100) fires only the first time — later calls
  /// find the model already installed and skip straight to generation.
  Future<List<GeneratedCard>> generateFromText(
    String sourceText, {
    void Function(int percent)? onDownloadProgress,
  });

  /// Suggests a clearer/tighter phrasing for a single existing card. Returns
  /// the *same* front/back back unchanged when the model judges the card
  /// already fine — callers should still let the user compare before
  /// applying it, rather than treating "unchanged" as a signal to skip the
  /// review step.
  Future<GeneratedCard> improveCard(
    String front,
    String back, {
    void Function(int percent)? onDownloadProgress,
  });
}

/// Model file is ungated on HuggingFace (Apache 2.0, no login/token
/// required) — deliberately chosen over Gemma to avoid asking every end
/// user to create a HuggingFace account just to use this feature. ~475MB,
/// downloaded once and cached; every later call is fully offline.
const kOnDeviceModelUrl =
    'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm';

class OnDeviceFlashcardGenerator implements FlashcardGenerator {
  static const _maxCards = 10;

  @override
  Future<List<GeneratedCard>> generateFromText(
    String sourceText, {
    void Function(int percent)? onDownloadProgress,
  }) async {
    final response = await _runSingleTurn(
      _buildGeneratePrompt(sourceText),
      onDownloadProgress: onDownloadProgress,
    );
    return parseGeneratedCards(response);
  }

  @override
  Future<GeneratedCard> improveCard(
    String front,
    String back, {
    void Function(int percent)? onDownloadProgress,
  }) async {
    final response = await _runSingleTurn(
      _buildImprovePrompt(front, back),
      onDownloadProgress: onDownloadProgress,
    );
    return parseImprovedCard(response);
  }

  /// Installs (idempotent — no-op after the first call) and drives a single
  /// prompt/response turn on the on-device model. Shared by both prompts so
  /// the install/session/close lifecycle only lives in one place.
  Future<String> _runSingleTurn(
    String prompt, {
    void Function(int percent)? onDownloadProgress,
  }) async {
    final builder = FlutterGemma.installModel(
      modelType: ModelType.qwen3,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(kOnDeviceModelUrl);
    await (onDownloadProgress != null
            ? builder.withProgress(onDownloadProgress)
            : builder)
        .install();

    final model = await FlutterGemma.getActiveModel(maxTokens: 2048);
    try {
      final session = await model.createSession(
        temperature: 0.3,
        maxOutputTokens: 1024,
      );
      try {
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        return await session.getResponse();
      } finally {
        await session.close();
      }
    } finally {
      await model.close();
    }
  }

  String _buildGeneratePrompt(String sourceText) => '''
You are a flashcard generator. Read the study material below and write concise question/answer flashcards covering its key facts. Generate at most $_maxCards cards.

Respond with ONLY a JSON array — no markdown code fences, no explanation before or after. Each element must be an object with exactly two string fields: "front" (the question) and "back" (the answer).

Study material:
$sourceText''';

  String _buildImprovePrompt(String front, String back) => '''
You are a flashcard quality reviewer. Given the flashcard below, suggest a clearer, tighter version — fix ambiguity, split up compound questions, tighten wording. If it's already good, return it unchanged.

Respond with ONLY a JSON object — no markdown code fences, no explanation before or after — with exactly two string fields: "front" and "back".

Current card:
front: $front
back: $back''';
}

/// Extracts flashcards from a model's raw text response. Models routinely
/// ignore "no markdown fences" instructions and/or add a sentence of preamble
/// — this tolerates both by locating the outermost `[...]` span rather than
/// requiring the whole response to be valid JSON on its own.
List<GeneratedCard> parseGeneratedCards(String rawResponse) {
  final start = rawResponse.indexOf('[');
  final end = rawResponse.lastIndexOf(']');
  if (start == -1 || end == -1 || end < start) {
    throw const FlashcardGenerationException(
      "The model's response didn't contain any cards. Try again, or use shorter/simpler source text.",
    );
  }

  final jsonSlice = rawResponse.substring(start, end + 1);
  final dynamic decoded;
  try {
    decoded = jsonDecode(jsonSlice);
  } on FormatException {
    throw const FlashcardGenerationException(
      "The model's response wasn't valid — try again.",
    );
  }

  if (decoded is! List) {
    throw const FlashcardGenerationException(
      "The model's response wasn't a list of cards — try again.",
    );
  }

  final cards = <GeneratedCard>[];
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final front = entry['front'];
    final back = entry['back'];
    if (front is! String || back is! String) continue;
    if (front.trim().isEmpty || back.trim().isEmpty) continue;
    cards.add(GeneratedCard(front: front.trim(), back: back.trim()));
  }

  if (cards.isEmpty) {
    throw const FlashcardGenerationException(
      'No usable cards came back from that text — try again with more content.',
    );
  }
  return cards;
}

/// Extracts a single improved card from a model's raw text response. Same
/// tolerant-slicing approach as [parseGeneratedCards], but locates the
/// outermost `{...}` object span instead of a `[...]` array.
GeneratedCard parseImprovedCard(String rawResponse) {
  final start = rawResponse.indexOf('{');
  final end = rawResponse.lastIndexOf('}');
  if (start == -1 || end == -1 || end < start) {
    throw const FlashcardGenerationException(
      "The model's response didn't contain a suggestion. Try again.",
    );
  }

  final jsonSlice = rawResponse.substring(start, end + 1);
  final dynamic decoded;
  try {
    decoded = jsonDecode(jsonSlice);
  } on FormatException {
    throw const FlashcardGenerationException(
      "The model's response wasn't valid — try again.",
    );
  }

  if (decoded is! Map) {
    throw const FlashcardGenerationException(
      "The model's response wasn't a single card — try again.",
    );
  }

  final front = decoded['front'];
  final back = decoded['back'];
  if (front is! String || back is! String || front.trim().isEmpty || back.trim().isEmpty) {
    throw const FlashcardGenerationException(
      "The model's suggestion was missing a front or back — try again.",
    );
  }
  return GeneratedCard(front: front.trim(), back: back.trim());
}
