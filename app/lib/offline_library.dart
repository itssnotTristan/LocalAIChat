import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const bundledPackIds = [
  'survival',
  'cooking',
  'coding',
  'electrical',
  'hunting',
  'first_aid',
];

class LibraryCard {
  LibraryCard({
    required this.id,
    required this.title,
    required this.summary,
    required this.steps,
    required this.source,
    required this.sourceUrl,
    required this.tags,
  });

  final String id;
  final String title;
  final String summary;
  final List<String> steps;
  final String source;
  final String sourceUrl;
  final List<String> tags;

  factory LibraryCard.fromJson(Map<String, dynamic> value) => LibraryCard(
    id: value['id'] as String,
    title: value['title'] as String,
    summary: value['summary'] as String,
    steps: (value['steps'] as List).cast<String>(),
    source: value['source'] as String,
    sourceUrl: value['sourceUrl'] as String,
    tags: (value['tags'] as List).cast<String>(),
  );

  String get searchable =>
      '$title $summary ${tags.join(' ')} ${steps.join(' ')}'.toLowerCase();
}

class LibraryPack {
  LibraryPack({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.cards,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final List<LibraryCard> cards;

  factory LibraryPack.fromJson(Map<String, dynamic> value) => LibraryPack(
    id: value['id'] as String,
    title: value['title'] as String,
    description: value['description'] as String,
    icon: value['icon'] as String,
    cards: (value['cards'] as List)
        .map(
          (item) =>
              LibraryCard.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

class LibraryHit {
  const LibraryHit(this.pack, this.card);
  final LibraryPack pack;
  final LibraryCard card;
}

/// Install copies a bundled reference pack into app-owned storage. Reading,
/// search, checklist progress, and retrieval never require a network request.
class OfflineLibraryRepository {
  OfflineLibraryRepository(this.supportDirectory, this.assets);

  final Directory supportDirectory;
  final AssetBundle assets;
  final Map<String, LibraryPack> catalog = {};
  final Set<String> installed = {};
  final Set<String> completed = {};
  final Set<String> favorites = {};
  final Map<String, String> notes = {};

  Directory get _packDirectory => Directory(
    '${supportDirectory.path}${Platform.pathSeparator}library_packs',
  );
  File get _stateFile => File(
    '${supportDirectory.path}${Platform.pathSeparator}library_state.json',
  );

  Future<void> load() async {
    catalog.clear();
    installed.clear();
    await _packDirectory.create(recursive: true);
    for (final id in bundledPackIds) {
      final bundled = await assets.loadString('assets/packs/$id.json');
      final pack = LibraryPack.fromJson(
        Map<String, dynamic>.from(jsonDecode(bundled) as Map),
      );
      if (pack.id != id || pack.cards.isEmpty) {
        throw FormatException('Invalid bundled pack: $id');
      }
      catalog[id] = pack;
      final file = _fileFor(id);
      if (!await file.exists()) continue;
      try {
        final saved = LibraryPack.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(await file.readAsString()) as Map,
          ),
        );
        if (saved.id == id && saved.cards.isNotEmpty) installed.add(id);
      } catch (_) {
        // A damaged local pack can be installed again from the bundled copy.
      }
    }
    if (await _stateFile.exists()) {
      try {
        final state = Map<String, dynamic>.from(
          jsonDecode(await _stateFile.readAsString()) as Map,
        );
        completed
          ..clear()
          ..addAll((state['completed'] as List? ?? []).cast<String>());
        favorites
          ..clear()
          ..addAll((state['favorites'] as List? ?? []).cast<String>());
        notes
          ..clear()
          ..addAll(
            (state['notes'] as Map? ?? {}).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
          );
      } catch (_) {
        completed.clear();
        favorites.clear();
        notes.clear();
      }
    }
  }

  File _fileFor(String id) =>
      File('${_packDirectory.path}${Platform.pathSeparator}$id.json');

  Future<void> install(String id) async {
    if (!catalog.containsKey(id)) throw ArgumentError.value(id, 'id');
    final bundled = await assets.loadString('assets/packs/$id.json');
    final temp = File('${_fileFor(id).path}.tmp');
    await temp.writeAsString(bundled, flush: true);
    if (await _fileFor(id).exists()) await _fileFor(id).delete();
    await temp.rename(_fileFor(id).path);
    installed.add(id);
  }

  Future<void> remove(String id) async {
    if (!catalog.containsKey(id)) throw ArgumentError.value(id, 'id');
    final file = _fileFor(id);
    if (await file.exists()) await file.delete();
    installed.remove(id);
  }

  Future<void> setCompleted(String cardId, int step, bool value) async {
    final key = '$cardId:$step';
    if (value) {
      completed.add(key);
    } else {
      completed.remove(key);
    }
    await _saveState();
  }

  Future<void> setFavorite(String cardId, bool value) async {
    if (value) {
      favorites.add(cardId);
    } else {
      favorites.remove(cardId);
    }
    await _saveState();
  }

  Future<void> setNote(String cardId, String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      notes.remove(cardId);
    } else {
      notes[cardId] = cleaned.length > 2000
          ? cleaned.substring(0, 2000)
          : cleaned;
    }
    await _saveState();
  }

  Future<void> _saveState() async {
    final temp = File('${_stateFile.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'completed': completed.toList(),
        'favorites': favorites.toList(),
        'notes': notes,
      }),
      flush: true,
    );
    await temp.rename(_stateFile.path);
  }

  List<LibraryHit> search(String query, {bool favoritesOnly = false}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length > 2);
    final hits = <LibraryHit>[];
    for (final id in bundledPackIds) {
      if (!installed.contains(id)) continue;
      final pack = catalog[id]!;
      for (final card in pack.cards) {
        if (favoritesOnly && !favorites.contains(card.id)) continue;
        if (words.every(card.searchable.contains)) {
          hits.add(LibraryHit(pack, card));
        }
      }
    }
    return hits;
  }

  /// Only relevant, installed, source-labeled facts enter a model prompt.
  /// This is reference data, never instructions to the assistant.
  String contextFor(String query) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length > 3)
        .toSet();
    if (words.isEmpty) return '';
    final ranked = <(int, LibraryHit)>[];
    for (final hit in search('')) {
      final searchable = hit.card.searchable;
      final score = words.where(searchable.contains).length;
      if (score > 0) {
        ranked.add((score, hit));
      }
    }
    ranked.sort((a, b) => b.$1.compareTo(a.$1));
    if (ranked.isEmpty) return '';
    return ranked
        .take(2)
        .map((item) {
          final card = item.$2.card;
          return '${card.title} (${item.$2.pack.title}): ${card.summary} '
              '${card.steps.take(3).join(' ')} Source: ${card.source} '
              '${card.sourceUrl}';
        })
        .join('\n');
  }
}
