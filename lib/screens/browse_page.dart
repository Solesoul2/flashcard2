// lib/screens/browse_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import models and widgets
import '../models/folder.dart';
import '../models/flashcard.dart';
import '../widgets/interactive_study_card.dart'; // Reusing this, but configured for Browse
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
      // Check if controller is attached before accessing page
      if (_pageController.hasClients) {
        final newIndex = _pageController.page?.round() ?? 0;
        if (newIndex != _currentPageIndex) {
          // Use mounted check before calling setState
          if (mounted) {
             setState(() {
               _currentPageIndex = newIndex;
             });
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

  // Optional: Add Edit/Delete functionality later if needed
  Future<void> _handleDeleteCard(BuildContext context, WidgetRef ref, Flashcard cardToDelete) async {
    if (cardToDelete.id == null) return;
     final confirm = await showConfirmationDialog(
       context: context,
       title: const Text('Confirm Delete'),
       content: const Text('Delete this flashcard permanently?'),
       confirmActionText: 'Delete',
       isDestructiveAction: true,
     );
     if (confirm == true && context.mounted) {
        try {
          // Call notifier's delete method
          await ref.read(browseProvider(widget.folder).notifier).deleteCard(cardToDelete.id!);
           if(context.mounted){
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flashcard deleted.')));
                // Provider update should trigger rebuild automatically
           }
        } catch (e) {
           if(context.mounted){
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting card: $e'), backgroundColor: Colors.red));
           }
        }
     }
   }
  // Future<void> _navigateToEdit(BuildContext context, WidgetRef ref, Flashcard cardToEdit) async { ... }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Watch the ASYNCHRONOUS browseProvider
    final browseStateAsync = ref.watch(browseProvider(widget.folder));

    return Scaffold( // Error fixed: Removed extra positional argument here if any existed implicitly
      appBar: AppBar(
        // Corrected string interpolation
        title: Text('Browse: ${widget.folder.name}'),
        // Card counter in app bar actions
        // Corrected escaping if any existed
        actions: [
           // Use valueOrNull to safely access data for counter
           if (browseStateAsync.valueOrNull?.isNotEmpty ?? false)
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 16.0),
               child: Center(
                 child: Text(
                   // Use PageController page for accuracy, ensure index is valid
                   '${(_pageController.hasClients ? (_pageController.page?.round() ?? 0) : _currentPageIndex) + 1}/${browseStateAsync.value!.length}',
                   style: theme.textTheme.bodyMedium?.copyWith(color: theme.appBarTheme.foregroundColor),
                 ),
               ),
             )
           else
             const SizedBox.shrink(), // Hide counter otherwise
        ], // Corrected list closing bracket
      ), // Corrected AppBar closing parenthesis
      // Use .when() to handle AsyncValue states
      body: browseStateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            // Corrected EdgeInsets syntax if it was broken
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
                 const SizedBox(height: 16),
                 Text('Error loading cards:', style: theme.textTheme.titleLarge),
                 const SizedBox(height: 8),
                 // Display the specific error message from the notifier
                 Text(err.toString().replaceFirst("Exception: ", ""), style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
                 const SizedBox(height: 24),
                 ElevatedButton.icon(
                     icon: const Icon(Icons.refresh),
                     label: const Text('Retry'),
                     // Invalidate the actual provider to retry loading
                     onPressed: () => ref.invalidate(browseProvider(widget.folder)),
                 )
              ], // Corrected Column children list closing bracket
            ), // Corrected Padding closing parenthesis
          ), // Corrected Center closing parenthesis
        ), // Corrected error closing parenthesis and added comma
        data: (cards) {
          // Check if the list received is empty
          if (cards.isEmpty) {
            return Center( // Corrected Center closing parenthesis
              child: Padding( // Corrected Padding closing parenthesis
                padding: const EdgeInsets.all(20.0), // Corrected EdgeInsets syntax if broken
                 child: Text(
                  'This folder has no flashcards to browse.',
                   textAlign: TextAlign.center,
                   style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                 ),
              ),
            ); // Corrected return closing parenthesis and added semicolon
          } // Corrected if closing brace

          // --- Display PageView for Browse ---
          return PageView.builder( // Corrected return closing parenthesis and added semicolon
            controller: _pageController,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              // Defensive check, although itemCount should be correct
              if (index >= cards.length) return const SizedBox.shrink();
              final card = cards[index];

              return InteractiveStudyCard(
                key: ValueKey('browse_card_${card.id}_$index'),
                flashcard: card,
                folder: widget.folder, // Pass folder context
                folderPath: const [], // Folder path not crucial for Browse view
                currentCardIndex: index + 1,
                totalCardCount: cards.length,
                isAnswerShown: true, // Always show answer in browse mode
                checklistItems: const [], // Pass empty list - checklist state not used/interactive
                answerMarkdownContent: card.answer, // Pass full answer
                onChecklistChanged: (itemIndex, isChecked) { /* No-op */ },
                onRatingColorCalculated: (id, color) { /* No-op */ },
                // Pass the delete handler (needs ref)
                onDelete: () => _handleDeleteCard(context, ref, card),
                 // Edit/Delete buttons are shown by default in InteractiveStudyCard's top bar.
              ); // Corrected InteractiveStudyCard closing parenthesis
            }, // Corrected itemBuilder closing brace and added comma
          ); // Corrected PageView.builder closing parenthesis
        }, // Corrected data closing brace
      ), // Corrected .when() closing parenthesis
    ); // Corrected Scaffold closing parenthesis
  } // Corrected build method closing brace
} // Corrected _BrowsePageState class closing brace