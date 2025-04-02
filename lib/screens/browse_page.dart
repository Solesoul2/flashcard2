// lib/screens/browse_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import models and widgets
import '../models/folder.dart';
import '../models/flashcard.dart';
// Import InteractiveStudyCard correctly
import '../widgets/interactive_study_card.dart';
// Import needed structures for dummy data (still needed for ParsedAnswerLine)
import '../providers/study_notifier.dart' show ParsedAnswerLine, AnswerLineType;
// Import the actual ASYNCHRONOUS notifier provider
import '../providers/browse_notifier.dart';
import '../utils/helpers.dart'; // For confirmation dialog if delete/edit is added

/// A screen to browse through flashcards in a folder using swipe navigation.
class BrowsePage extends ConsumerStatefulWidget {
  final Folder folder;

  const BrowsePage({required this.folder, Key? key}) : super(key: key);

  @override
  ConsumerState<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends ConsumerState<BrowsePage> {
  late PageController _pageController;
  int _currentPageIndex = 0; // Track current page for counter display

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(() {
      if (_pageController.hasClients) {
        final newIndex = _pageController.page?.round() ?? 0;
        if (newIndex != _currentPageIndex) {
          if (mounted) {
             setState(() { _currentPageIndex = newIndex; });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Delete Card Handler (remains the same)
  Future<void> _handleDeleteCard(BuildContext context, WidgetRef ref, Flashcard cardToDelete) async {
    if (cardToDelete.id == null) return;
     final confirm = await showConfirmationDialog( context: context, title: const Text('Confirm Delete'), content: const Text('Delete this flashcard permanently?'), confirmActionText: 'Delete', isDestructiveAction: true, );
     if (confirm == true && context.mounted) {
        try {
          await ref.read(browseProvider(widget.folder).notifier).deleteCard(cardToDelete.id!);
           if(context.mounted){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flashcard deleted.'))); }
        } catch (e) { if(context.mounted){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting card: $e'), backgroundColor: Colors.red)); } }
     }
   }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final browseStateAsync = ref.watch(browseProvider(widget.folder));

    return Scaffold(
      appBar: AppBar(
        title: Text('Browse: ${widget.folder.name}'),
        actions: [
           if (browseStateAsync.valueOrNull?.isNotEmpty ?? false)
             Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Center( child: Text( '${(_pageController.hasClients ? (_pageController.page?.round() ?? 0) : _currentPageIndex) + 1}/${browseStateAsync.value!.length}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.appBarTheme.foregroundColor), ), ), )
           else const SizedBox.shrink(),
        ],
      ),
      body: browseStateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center( /* Error UI */
          child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48), const SizedBox(height: 16), Text('Error loading cards:', style: theme.textTheme.titleLarge), const SizedBox(height: 8), Text(err.toString().replaceFirst("Exception: ", ""), style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center), const SizedBox(height: 24), ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: () => ref.invalidate(browseProvider(widget.folder)), ) ], ), ),
        ),
        data: (cards) {
          if (cards.isEmpty) { /* Empty State UI */
            return Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Text( 'This folder has no flashcards to browse.', textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]), ), ), );
          }

          // Display PageView for Browse
          return PageView.builder(
            controller: _pageController,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              if (index >= cards.length) return const SizedBox.shrink();
              final card = cards[index];

              // *** MODIFIED: Pass settings parameters to InteractiveStudyCard ***
              return InteractiveStudyCard(
                key: ValueKey('browse_card_${card.id}_$index'),
                flashcard: card,
                folder: widget.folder,
                folderPath: const [], // Not crucial for Browse view
                currentCardIndex: index + 1,
                totalCardCount: cards.length,
                isAnswerShown: true, // Always show answer in browse mode

                // Provide the ordered answer lines (simple for browse)
                orderedAnswerLines: [
                   ParsedAnswerLine(type: AnswerLineType.text, textContent: card.answer)
                ],
                // Checklist state is not interactive here, pass empty list
                checklistItemsState: const [],

                // --- NEW: Provide default values for settings ---
                // Setting these to false ensures all content is immediately visible
                // in browse mode, consistent with isAnswerShown being true.
                setting1Active: false,
                setting2Active: false,
                // --- End NEW ---

                // Callbacks
                onChecklistChanged: (itemIndex, isChecked) { /* No-op in browse */ },
                onRatingColorCalculated: (id, color) { /* No-op in browse */ },
                onDelete: () => _handleDeleteCard(context, ref, card),
                // onEditComplete might be needed if editing is added to browse mode later
              );
              // *** END MODIFICATION ***
            },
          );
        },
      ),
    );
  }
}