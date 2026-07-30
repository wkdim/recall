import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../ai/flashcard_generator.dart';
import '../cloze/cloze_parser.dart';
import '../database/database.dart';
import '../health/deck_health.dart';
import '../importexport/deck_transfer.dart';
import '../media/media_picker.dart';
import '../media/media_storage.dart';
import '../tags/tag_utils.dart';
import 'generate_cards_screen.dart';

class EditDeckScreen extends StatefulWidget {
  final Deck? deck;

  /// Injectable so tests can attach media without hitting the real picker
  /// plugins, which have no platform channel handler in this test host.
  final MediaPicker? mediaPicker;

  /// Overrides where picked media gets copied to. Tests must pass a temp
  /// directory here — leaving this null makes [MediaStorage] call the real
  /// `path_provider` plugin, which hangs indefinitely in a plain
  /// `flutter_test` host (no engine, same class of issue as `AppDatabase()`).
  final Directory? mediaStorageDir;

  /// Injectable so tests can exercise "Improve with AI" without a real
  /// on-device model — flutter_test has no platform channel for it, same
  /// reason as [mediaPicker] above.
  final FlashcardGenerator? flashcardGenerator;

  const EditDeckScreen({
    super.key,
    this.deck,
    this.mediaPicker,
    this.mediaStorageDir,
    this.flashcardGenerator,
  });

  @override
  State<EditDeckScreen> createState() => _EditDeckScreenState();
}

class _EditDeckScreenState extends State<EditDeckScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _frontController = TextEditingController();
  final _backController = TextEditingController();
  final _tagsController = TextEditingController();
  final _searchController = TextEditingController();
  final _mediaStorage = MediaStorage();
  late final MediaPicker _mediaPicker = widget.mediaPicker ?? DevicePicker();
  late final FlashcardGenerator _flashcardGenerator =
      widget.flashcardGenerator ?? OnDeviceFlashcardGenerator();
  int? _deckId;
  bool _isCloze = false;
  String _searchQuery = '';
  String? _frontImagePath;
  String? _backImagePath;
  String? _frontAudioPath;
  String? _backAudioPath;

  @override
  void initState() {
    super.initState();
    if (widget.deck != null) {
      _deckId = widget.deck!.id;
      _nameController.text = widget.deck!.name;
      _descController.text = widget.deck!.description ?? '';
    }
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _frontController.dispose();
    _backController.dispose();
    _tagsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String? get _trimmedDesc {
    final s = _descController.text.trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _addCard(AppDatabase db) async {
    final front = _frontController.text.trim();
    final back = _backController.text.trim();
    if (front.isEmpty) return;
    if (!_isCloze && back.isEmpty) return;
    if (_isCloze && !hasClozeMarker(front)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrap the hidden part in {{c::like this}}')),
      );
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a deck name first')),
      );
      return;
    }

    if (_deckId == null) {
      final deck = await db.into(db.decks).insertReturning(
        DecksCompanion.insert(
          name: name,
          description: drift.Value(_trimmedDesc),
        ),
      );
      setState(() => _deckId = deck.id);
    }

    final tags = encodeTags(parseTags(_tagsController.text));
    await db.into(db.cards).insert(
      CardsCompanion.insert(
        deckId: _deckId!,
        front: front,
        back: back,
        tags: drift.Value(tags.isEmpty ? null : tags),
        isCloze: drift.Value(_isCloze),
        frontImagePath: drift.Value(_frontImagePath),
        backImagePath: drift.Value(_backImagePath),
        frontAudioPath: drift.Value(_frontAudioPath),
        backAudioPath: drift.Value(_backAudioPath),
      ),
    );

    _frontController.clear();
    _backController.clear();
    _tagsController.clear();
    setState(() {
      _frontImagePath = null;
      _backImagePath = null;
      _frontAudioPath = null;
      _backAudioPath = null;
    });
  }

  Future<void> _pickImage(bool isFront) async {
    final pickedPath = await _mediaPicker.pickImage();
    if (pickedPath == null) return;
    final stored = await _mediaStorage.copyIntoAppStorage(pickedPath, targetDir: widget.mediaStorageDir);
    setState(() {
      if (isFront) {
        _frontImagePath = stored;
      } else {
        _backImagePath = stored;
      }
    });
  }

  Future<void> _pickAudio(bool isFront) async {
    final pickedPath = await _mediaPicker.pickAudio();
    if (pickedPath == null) return;
    final stored = await _mediaStorage.copyIntoAppStorage(pickedPath, targetDir: widget.mediaStorageDir);
    setState(() {
      if (isFront) {
        _frontAudioPath = stored;
      } else {
        _backAudioPath = stored;
      }
    });
  }

  Future<void> _editCard(AppDatabase db, Card card) async {
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (_) => _EditCardDialog(
        front: card.front,
        back: card.back,
        tags: parseTags(card.tags).join(', '),
        generator: _flashcardGenerator,
      ),
    );
    if (result == null) return;
    final (front, back, tags) = result;
    if (front.isEmpty || back.isEmpty) return;
    await db.updateCard(card.id, front, back, tags: encodeTags(parseTags(tags)));
  }

  void _confirmDeleteCard(AppDatabase db, Card card) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete card?'),
        content: Text('Permanently delete "${card.front}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              db.deleteCard(card.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportDeck(AppDatabase db) async {
    final deckId = _deckId;
    if (deckId == null) return;

    final format = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Export deck', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV (front, back only)'),
              subtitle: const Text('Compatible with most flashcard apps'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('JSON (full backup)'),
              subtitle: const Text('Includes review progress'),
              onTap: () => Navigator.pop(context, 'json'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (format == null) return;

    final deckName = _nameController.text.trim();
    final cards = await (db.select(db.cards)..where((c) => c.deckId.equals(deckId))).get();

    final String content;
    final String extension;
    if (format == 'json') {
      content = encodeDeckToJson(DeckExport(
        name: deckName,
        description: _trimmedDesc,
        cards: cards
            .map((c) => CardRecord(
                  front: c.front,
                  back: c.back,
                  easeFactor: c.easeFactor,
                  interval: c.interval,
                  repetitions: c.repetitions,
                  nextReview: c.nextReview,
                ))
            .toList(),
      ));
      extension = 'json';
    } else {
      content = encodeCardsToCsv(cards
          .map((c) => CardRecord(front: c.front, back: c.back, nextReview: c.nextReview))
          .toList());
      extension = 'csv';
    }

    final safeName = deckName.isEmpty ? 'deck' : deckName.replaceAll(RegExp(r'[^\w\- ]'), '');
    final dir = await getTemporaryDirectory();
    final file = File(path.join(dir.path, '$safeName.$extension'));
    await file.writeAsString(content);

    if (!mounted) return;
    await Share.shareXFiles([XFile(file.path)], subject: '$safeName.$extension');
  }

  Future<void> _generateFromText() async {
    final deckId = _deckId;
    if (deckId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GenerateCardsScreen(deckId: deckId)),
    );
  }

  Future<void> _importCards(AppDatabase db) async {
    final deckId = _deckId;
    if (deckId == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
    );
    final pickedPath = result?.files.single.path;
    if (pickedPath == null) return;

    final file = File(pickedPath);
    final content = await file.readAsString();
    final isJson = pickedPath.toLowerCase().endsWith('.json');

    List<CardRecord> imported;
    try {
      imported = isJson ? decodeDeckFromJson(content).cards : decodeCardsFromCsv(content);
    } on InvalidDeckFileException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import: ${e.message}')),
      );
      return;
    }

    if (imported.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cards found in that file')),
      );
      return;
    }

    await db.batch((batch) {
      batch.insertAll(
        db.cards,
        imported.map((c) => CardsCompanion.insert(
              deckId: deckId,
              front: c.front,
              back: c.back,
              easeFactor: drift.Value(c.easeFactor),
              interval: drift.Value(c.interval),
              repetitions: drift.Value(c.repetitions),
              nextReview: drift.Value(c.nextReview),
            )),
      );
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported ${imported.length} card${imported.length == 1 ? '' : 's'}')),
    );
  }

  Future<void> _save(AppDatabase db) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a deck name')),
      );
      return;
    }

    if (_deckId == null) {
      await db.into(db.decks).insert(
        DecksCompanion.insert(name: name, description: drift.Value(_trimmedDesc)),
      );
    } else {
      await db.updateDeck(_deckId!, name, _trimmedDesc);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deck != null ? 'Edit Deck' : 'New Deck'),
        actions: [
          if (_deckId != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'export') _exportDeck(db);
                if (value == 'import') _importCards(db);
                if (value == 'generate') _generateFromText();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'generate',
                  child: ListTile(
                    leading: Icon(Icons.auto_awesome_outlined),
                    title: Text('Generate from text'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.ios_share),
                    title: Text('Export deck'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: Icon(Icons.file_upload_outlined),
                    title: Text('Import cards'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: () => _save(db),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel(context, 'DECK INFO'),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Deck Name',
                prefixIcon: Icon(Icons.style_outlined),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel(context, 'ADD CARDS'),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isCloze,
              onChanged: (v) => setState(() => _isCloze = v),
              title: const Text('Cloze deletion'),
              subtitle: Text(
                _isCloze
                    ? 'Wrap the hidden part: "The capital is {{c::Paris}}"'
                    : 'A fill-in-the-blank card instead of front/back',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _frontController,
              decoration: InputDecoration(
                labelText: _isCloze ? 'Text with {{c::hidden part}}' : 'Front (question)',
                prefixIcon: const Icon(Icons.help_outline),
              ),
            ),
            const SizedBox(height: 6),
            _MediaAttachRow(
              imagePath: _frontImagePath,
              audioPath: _frontAudioPath,
              onPickImage: () => _pickImage(true),
              onPickAudio: () => _pickAudio(true),
              onRemoveImage: () => setState(() => _frontImagePath = null),
              onRemoveAudio: () => setState(() => _frontAudioPath = null),
            ),
            const SizedBox(height: 12),
            if (!_isCloze) ...[
              TextField(
                controller: _backController,
                decoration: const InputDecoration(
                  labelText: 'Back (answer)',
                  prefixIcon: Icon(Icons.lightbulb_outline),
                ),
                onSubmitted: (_) => _addCard(db),
              ),
              const SizedBox(height: 6),
              _MediaAttachRow(
                imagePath: _backImagePath,
                audioPath: _backAudioPath,
                onPickImage: () => _pickImage(false),
                onPickAudio: () => _pickAudio(false),
                onRemoveImage: () => setState(() => _backImagePath = null),
                onRemoveAudio: () => setState(() => _backAudioPath = null),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (optional, comma-separated)',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
              onSubmitted: (_) => _addCard(db),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _addCard(db),
              icon: const Icon(Icons.add),
              label: const Text('Add Card'),
            ),
            if (_deckId != null) ...[
              const SizedBox(height: 28),
              StreamBuilder<List<Card>>(
                stream: (db.select(db.cards)
                      ..where((c) => c.deckId.equals(_deckId!)))
                    .watch(),
                builder: (context, snap) {
                  final allCards = snap.data ?? [];
                  final cards = allCards
                      .where((c) => cardMatchesQuery(
                            front: c.front,
                            back: c.back,
                            tags: c.tags,
                            query: _searchQuery,
                          ))
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (allCards.isNotEmpty) ...[
                        _DeckHealthCard(cards: allCards),
                        const SizedBox(height: 20),
                      ],
                      _sectionLabel(context, 'YOUR CARDS  (${allCards.length})'),
                      const SizedBox(height: 10),
                      if (allCards.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              labelText: 'Search cards',
                              prefixIcon: Icon(Icons.search),
                              isDense: true,
                            ),
                          ),
                        ),
                      if (allCards.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No cards yet',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      else if (cards.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No cards match "$_searchQuery"',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      else
                        ...cards.asMap().entries.map((entry) {
                          final i = entry.key;
                          final card = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colorScheme.outlineVariant),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                onTap: () => _editCard(db, card),
                                contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                                leading: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        card.isCloze ? maskCloze(card.front) : card.front,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (card.isCloze) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'CLOZE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: colorScheme.onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      card.isCloze ? revealCloze(card.front) : card.back,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (parseTags(card.tags).isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Wrap(
                                          spacing: 4,
                                          children: parseTags(card.tags)
                                              .map((t) => Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: colorScheme.primaryContainer,
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: Text(
                                                      t,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: colorScheme.primary,
                                                      ),
                                                    ),
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                  ],
                                ),
                                isThreeLine: parseTags(card.tags).isNotEmpty,
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: colorScheme.error,
                                    size: 20,
                                  ),
                                  tooltip: 'Delete card',
                                  onPressed: () => _confirmDeleteCard(db, card),
                                ),
                                dense: true,
                              ),
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _EditCardDialog extends StatefulWidget {
  final String front;
  final String back;
  final String tags;
  final FlashcardGenerator generator;
  const _EditCardDialog({
    required this.front,
    required this.back,
    required this.generator,
    this.tags = '',
  });

  @override
  State<_EditCardDialog> createState() => _EditCardDialogState();
}

class _EditCardDialogState extends State<_EditCardDialog> {
  late final _frontController = TextEditingController(text: widget.front);
  late final _backController = TextEditingController(text: widget.back);
  late final _tagsController = TextEditingController(text: widget.tags);

  bool _improving = false;
  String? _improveError;
  GeneratedCard? _suggestion;

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _improveWithAi() async {
    setState(() {
      _improving = true;
      _improveError = null;
      _suggestion = null;
    });
    try {
      final suggestion = await widget.generator.improveCard(
        _frontController.text,
        _backController.text,
      );
      if (!mounted) return;
      setState(() => _suggestion = suggestion);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _improveError = e is FlashcardGenerationException
            ? e.message
            : "Couldn't get a suggestion — check your connection and try again.";
      });
    } finally {
      if (mounted) setState(() => _improving = false);
    }
  }

  void _acceptSuggestion() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    setState(() {
      _frontController.text = suggestion.front;
      _backController.text = suggestion.back;
      _suggestion = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Edit Card'),
      content: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('editCardFrontField'),
            controller: _frontController,
            decoration: const InputDecoration(labelText: 'Front (question)'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('editCardBackField'),
            controller: _backController,
            decoration: const InputDecoration(labelText: 'Back (answer)'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('editCardTagsField'),
            controller: _tagsController,
            decoration: const InputDecoration(labelText: 'Tags (comma-separated)'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('improveWithAi'),
              onPressed: _improving ? null : _improveWithAi,
              icon: _improving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(_improving ? 'Improving…' : 'Improve with AI'),
            ),
          ),
          if (_improveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _improveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          if (_suggestion != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Suggested', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(_suggestion!.front),
                  const SizedBox(height: 4),
                  Text(_suggestion!.back, style: const TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const Key('dismissSuggestion'),
                        onPressed: () => setState(() => _suggestion = null),
                        child: const Text('Dismiss'),
                      ),
                      FilledButton(
                        key: const Key('useSuggestion'),
                        onPressed: _acceptSuggestion,
                        child: const Text('Use This'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('editCardCancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('editCardSave'),
          onPressed: () => Navigator.pop(
            context,
            (_frontController.text.trim(), _backController.text.trim(), _tagsController.text.trim()),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DeckHealthCard extends StatelessWidget {
  final List<Card> cards;
  const _DeckHealthCard({required this.cards});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final report = computeDeckHealth(cards);
    final scoreColor = report.score >= 80
        ? colorScheme.primary
        : report.score >= 50
            ? colorScheme.tertiary
            : colorScheme.error;

    final issues = <String>[
      if (report.duplicateCount > 0) '${report.duplicateCount} duplicate card${report.duplicateCount == 1 ? '' : 's'}',
      if (report.tooLongCount > 0) '${report.tooLongCount} card${report.tooLongCount == 1 ? '' : 's'} too long',
      if (report.overdueCount > 0) '${report.overdueCount} card${report.overdueCount == 1 ? '' : 's'} overdue',
      if (report.neverReviewedCount > 0) '${report.neverReviewedCount} never reviewed',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(
                '${report.score}',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scoreColor),
              ),
              Text(
                'HEALTH',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: issues.isEmpty
                ? Text(
                    'No issues found',
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: issues
                        .map((issue) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '• $issue',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MediaAttachRow extends StatelessWidget {
  final String? imagePath;
  final String? audioPath;
  final VoidCallback onPickImage;
  final VoidCallback onPickAudio;
  final VoidCallback onRemoveImage;
  final VoidCallback onRemoveAudio;

  const _MediaAttachRow({
    required this.imagePath,
    required this.audioPath,
    required this.onPickImage,
    required this.onPickAudio,
    required this.onRemoveImage,
    required this.onRemoveAudio,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (imagePath == null)
          TextButton.icon(
            onPressed: onPickImage,
            icon: const Icon(Icons.image_outlined, size: 16),
            label: const Text('Add image'),
          )
        else
          Chip(
            avatar: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(File(imagePath!), width: 20, height: 20, fit: BoxFit.cover),
            ),
            label: const Text('Image attached'),
            onDeleted: onRemoveImage,
          ),
        if (audioPath == null)
          TextButton.icon(
            onPressed: onPickAudio,
            icon: const Icon(Icons.audiotrack_outlined, size: 16),
            label: const Text('Add audio'),
          )
        else
          Chip(
            avatar: Icon(Icons.audiotrack, size: 16, color: colorScheme.primary),
            label: Text(path.basename(audioPath!), overflow: TextOverflow.ellipsis),
            onDeleted: onRemoveAudio,
          ),
      ],
    );
  }
}
