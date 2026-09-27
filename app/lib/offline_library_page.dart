import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'glass_design.dart';
import 'offline_library.dart';
import 'app_issue.dart';

class OfflineLibraryPage extends StatefulWidget {
  const OfflineLibraryPage({
    required this.library,
    required this.onAsk,
    super.key,
  });

  final OfflineLibraryRepository library;
  final void Function(String) onAsk;

  @override
  State<OfflineLibraryPage> createState() => _OfflineLibraryPageState();
}

class _OfflineLibraryPageState extends State<OfflineLibraryPage> {
  final search = TextEditingController();
  bool favoritesOnly = false;
  bool urgentOnly = false;
  String? workingPack;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> togglePack(String id) async {
    setState(() => workingPack = id);
    try {
      if (widget.library.installed.contains(id)) {
        await widget.library.remove(id);
      } else {
        await widget.library.install(id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppIssue.from(error, area: IssueArea.app).display),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => workingPack = null);
    }
  }

  void ask(LibraryCard card) {
    widget.onAsk(
      'Using my offline Library card "${card.title}", explain it in a practical way.',
    );
    Navigator.of(context).pop();
  }

  Future<void> editNote(LibraryCard card) async {
    final controller = TextEditingController(
      text: widget.library.notes[card.id] ?? '',
    );
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('My note · ${card.title}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Add a location, practice result, or reminder…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await widget.library.setNote(card.id, saved);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    final results = library
        .search(search.text, favoritesOnly: favoritesOnly)
        .where(
          (hit) =>
              !urgentOnly ||
              const {
                'survival',
                'electrical',
                'first_aid',
              }.contains(hit.pack.id),
        )
        .toList();
    return Stack(
      children: [
        const Positioned.fill(child: GlassBackground()),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Offline Library'),
            backgroundColor: Colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              GlassSurface(
                child: Row(
                  children: [
                    const Icon(Icons.offline_bolt_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${library.installed.length} of ${library.catalog.length} packs installed · available without internet',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Packs', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...bundledPackIds.map((id) {
                final pack = library.catalog[id]!;
                final isInstalled = library.installed.contains(id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassSurface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    radius: 16,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_iconFor(pack.icon)),
                      title: Text(pack.title),
                      subtitle: Text(
                        '${pack.cards.length} field cards · ${pack.description}',
                      ),
                      trailing: workingPack == id
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed: workingPack != null
                                  ? null
                                  : () => unawaited(togglePack(id)),
                              child: Text(isInstalled ? 'Remove' : 'Install'),
                            ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Search installed cards',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(search.clear),
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Saved cards'),
                    avatar: const Icon(Icons.bookmark_outline, size: 18),
                    selected: favoritesOnly,
                    onSelected: (value) =>
                        setState(() => favoritesOnly = value),
                  ),
                  FilterChip(
                    label: const Text('Urgent basics'),
                    avatar: const Icon(Icons.priority_high, size: 18),
                    selected: urgentOnly,
                    onSelected: (value) => setState(() => urgentOnly = value),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    library.installed.isEmpty
                        ? 'Install a pack above to read and search it offline.'
                        : 'No cards match. Try a shorter search.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ...results.map(
                (hit) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassSurface(
                    padding: EdgeInsets.zero,
                    radius: 18,
                    child: ExpansionTile(
                      title: Text(hit.card.title),
                      subtitle: Text(hit.pack.title),
                      trailing: IconButton(
                        tooltip: library.favorites.contains(hit.card.id)
                            ? 'Remove saved card'
                            : 'Save card',
                        icon: Icon(
                          library.favorites.contains(hit.card.id)
                              ? Icons.bookmark
                              : Icons.bookmark_outline,
                        ),
                        onPressed: () async {
                          await library.setFavorite(
                            hit.card.id,
                            !library.favorites.contains(hit.card.id),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(hit.card.summary),
                          ),
                        ),
                        for (
                          var index = 0;
                          index < hit.card.steps.length;
                          index++
                        )
                          CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(hit.card.steps[index]),
                            value: library.completed.contains(
                              '${hit.card.id}:$index',
                            ),
                            onChanged: (value) async {
                              await library.setCompleted(
                                hit.card.id,
                                index,
                                value ?? false,
                              );
                              if (mounted) setState(() {});
                            },
                          ),
                        if (library.notes[hit.card.id]?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'My note: ${library.notes[hit.card.id]}',
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Source: ${hit.card.source}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Wrap(
                                spacing: 4,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => unawaited(
                                      launchUrl(
                                        Uri.parse(hit.card.sourceUrl),
                                        mode: LaunchMode.externalApplication,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 16,
                                    ),
                                    label: const Text('Source'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => editNote(hit.card),
                                    icon: const Icon(Icons.edit_note, size: 16),
                                    label: const Text('My note'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => ask(hit.card),
                                    icon: const Icon(
                                      Icons.chat_bubble_outline,
                                      size: 16,
                                    ),
                                    label: const Text('Ask AI'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

IconData _iconFor(String name) => switch (name) {
  'backpack' => Icons.backpack_outlined,
  'restaurant' => Icons.restaurant_outlined,
  'code' => Icons.code,
  'bolt' => Icons.bolt_outlined,
  'forest' => Icons.forest_outlined,
  'medical_services' => Icons.medical_services_outlined,
  _ => Icons.menu_book_outlined,
};
