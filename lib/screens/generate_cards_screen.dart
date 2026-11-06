import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ai/flashcard_generator.dart';
import '../database/database.dart';

class GenerateCardsScreen extends StatefulWidget {
  final int deckId;

  /// Injectable so tests can exercise this screen without a real on-device
  /// model - flutter_test has no platform channel for it, same reason
  /// `MediaPicker`/`ReminderScheduler` are abstracted elsewhere in this app.
  final FlashcardGenerator? generator;

  const GenerateCardsScreen({super.key, required this.deckId, this.generator});

  @override
  State<GenerateCardsScreen> createState() => _GenerateCardsScreenState();
}

enum _Status { idle, busy, reviewing, error }

class _GenerateCardsScreenState extends State<GenerateCardsScreen> {
  late final FlashcardGenerator _generator =
      widget.generator ?? OnDeviceFlashcardGenerator();
  final _textController = TextEditingController();

  _Status _status = _Status.idle;
  int _downloadPercent = 0;
  String? _errorMessage;
  List<GeneratedCard> _generated = [];
  late List<bool> _selected;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _status = _Status.busy;
      _downloadPercent = 0;
      _errorMessage = null;
    });

    try {
      final cards = await _generator.generateFromText(
        text,
        onDownloadProgress: (percent) {
          if (mounted) setState(() => _downloadPercent = percent);
        },
      );
      if (!mounted) return;
      setState(() {
        _generated = cards;
        _selected = List.filled(cards.length, true);
        _status = _Status.reviewing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is FlashcardGenerationException
            ? e.message
            : "Couldn't generate cards. Check your connection (needed once, to download the on-device model) and try again.";
        _status = _Status.error;
      });
    }
  }

  Future<void> _addSelected(AppDatabase db) async {
    for (var i = 0; i < _generated.length; i++) {
      if (!_selected[i]) continue;
      final card = _generated[i];
      await db.into(db.cards).insert(
            CardsCompanion.insert(
              deckId: widget.deckId,
              front: card.front,
              back: card.back,
            ),
          );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Generate from Text')),
      body: switch (_status) {
        _Status.idle => _buildInput(),
        _Status.busy => _buildBusy(),
        _Status.error => _buildError(),
        _Status.reviewing => _buildReview(db),
      },
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Paste notes, an article, or any study text below. Cards are generated on your device, and nothing leaves your phone.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Paste your text here…',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _generate,
            child: const Text('Generate Cards'),
          ),
        ],
      ),
    );
  }

  Widget _buildBusy() {
    final downloading = _downloadPercent > 0 && _downloadPercent < 100;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (downloading)
              Column(
                children: [
                  LinearProgressIndicator(value: _downloadPercent / 100),
                  const SizedBox(height: 12),
                  Text('Downloading on-device model: $_downloadPercent%\n(one-time, ~475MB, then fully offline)',
                      textAlign: TextAlign.center),
                ],
              )
            else
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Generating flashcards…'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage ?? 'Something went wrong.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _status = _Status.idle),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReview(AppDatabase db) {
    final selectedCount = _selected.where((s) => s).length;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _generated.length,
            itemBuilder: (context, index) {
              final card = _generated[index];
              return CheckboxListTile(
                value: _selected[index],
                onChanged: (v) => setState(() => _selected[index] = v ?? false),
                title: Text(card.front),
                subtitle: Text(card.back),
              );
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: selectedCount == 0 ? null : () => _addSelected(db),
            child: Text(selectedCount == 0 ? 'Add Cards' : 'Add $selectedCount Card${selectedCount == 1 ? '' : 's'}'),
          ),
        ),
      ],
    );
  }
}
