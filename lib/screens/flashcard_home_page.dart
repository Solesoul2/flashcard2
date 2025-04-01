// lib/screens/flashcard_home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import models, providers, widgets, and screens
import '../models/flashcard.dart';
import '../models/folder.dart'; // Needed for the static uncategorized context
import '../providers/uncategorized_cards_notifier.dart'; // Import the MANUAL notifier provider
import '../utils/helpers.dart';
import '../widgets/static_flashcard_list_tile.dart';
import 'flashcard_edit_page.dart';

// Changed to ConsumerWidget
class FlashcardHomePage extends ConsumerWidget {
  // Represents the logical "folder" context for uncategorized cards.
  // Used when navigating to the edit page to add a new uncategorized card.
  static const Folder uncategorizedFolderContext = Folder(id: null, name: "Uncategorized");

  const FlashcardHomePage({Key? key}) : super(key: key);

  // --- Navigation ---

  Future<void> _navigateToFlashcardEdit(BuildContext context, WidgetRef ref, {Flashcard? flashcard}) async {
    // Navigate to the edit page, passing the special 'uncategorized' context
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => FlashcardEditPage(
              folder: FlashcardHomePage.uncategorizedFolderContext,
              flashcard: flashcard,
          )
      ),
    );
    // If the edit page indicated a change was made (e.g., card added/edited),
    // invalidate the provider to refresh the list on this screen.
    if (result == true && context.mounted) {
        // Use the manually defined provider name
        ref.invalidate(uncategorizedCardsNotifierProvider);
    }
  }

  // --- Actions (Interact with Notifier) ---

  Future<void> _handleDeleteFlashcard(BuildContext context, WidgetRef ref, Flashcard flashcard) async {
     if (flashcard.id == null) return; // Cannot delete card without an ID

     // Show confirmation dialog before deleting
     final bool confirmed = await showConfirmationDialog(
       context: context,
       title: const Text('Confirm Delete'),
       content: const Text('Are you sure you want to delete this flashcard?'),
       confirmActionText: 'Delete',
       isDestructiveAction: true,
     );

     if (confirmed == true && context.mounted) {
       try {
         // Call the notifier method to delete the card. Use ref.read for actions.
         // Use the manually defined provider name
         await ref.read(uncategorizedCardsNotifierProvider.notifier).deleteCard(flashcard.id!);

         // Show success feedback if still mounted after the async operation
         if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Flashcard deleted.'), duration: Duration(seconds: 2))
           );
           // No manual refresh needed here; the notifier handles its state update upon success.
         }
       } catch (e) {
         // Show error feedback if still mounted
         if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error deleting flashcard: ${e.toString().replaceFirst("Exception: ","")}'), backgroundColor: Colors.red)
           );
         }
       }
     }
   }

  // --- Build Method ---

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the provider state. ref.watch rebuilds the widget when the state changes.
    // Use the manually defined provider name
    final AsyncValue<List<Flashcard>> asyncFlashcards = ref.watch(uncategorizedCardsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Uncategorized Flashcards'),
        // Theme applied globally
      ),
      body: RefreshIndicator(
        // On pull-to-refresh, invalidate the provider to trigger a data refetch.
        // Use the manually defined provider name
        onRefresh: () async => ref.invalidate(uncategorizedCardsNotifierProvider),
        // Use .when to handle the different states of the AsyncValue (loading, error, data)
        child: asyncFlashcards.when(
          // Loading State UI: Show a progress indicator
          loading: () => const Center(child: CircularProgressIndicator()),

          // Error State UI: Show an error message and a retry button
          error: (error, stackTrace) {
             // Log the error for debugging
             print("Error loading uncategorized cards UI: $error\n$stackTrace");
             // Display user-friendly error UI
             return Center(
               child: Padding(
                 padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 48),
                      const SizedBox(height: 16),
                      Text(
                         'Error loading flashcards.',
                         style: Theme.of(context).textTheme.headlineSmall,
                         textAlign: TextAlign.center,
                       ),
                       const SizedBox(height: 8),
                      Text(
                        'Please check your connection and pull down to refresh.\n(${error.toString().replaceFirst("Exception: ","")})',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        // Invalidate provider on retry button press
                        // Use the manually defined provider name
                        onPressed: () => ref.invalidate(uncategorizedCardsNotifierProvider),
                      )
                    ]
                  ),
               ),
             );
          },

          // Data State UI: Display the list of flashcards or an empty state message
          data: (flashcards) {
            // Handle Empty State
            if (flashcards.isEmpty) {
              // Provide a user-friendly message when no cards are found
              return LayoutBuilder(
                 builder: (context, constraints) {
                    // Ensure the refresh indicator works even when the list is empty
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                           child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Text(
                                'No uncategorized flashcards found.\nAdd one using the "+" button below.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                              ),
                           )
                        ),
                      ),
                    );
                 }
              );
            }

            // Display the list using ListView.builder and the reusable tile widget
            return ListView.builder(
               padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
               itemCount: flashcards.length,
               itemBuilder: (context, index) {
                  final flashcard = flashcards[index];
                  return StaticFlashcardListTile(
                    flashcard: flashcard,
                    // Wire up edit and delete actions
                    onEdit: () => _navigateToFlashcardEdit(context, ref, flashcard: flashcard),
                    onDelete: () => _handleDeleteFlashcard(context, ref, flashcard),
                    // isSelected is not relevant on this screen
                  );
               },
            );
          },
        ),
      ),
      // FAB uses theme styles
      floatingActionButton: FloatingActionButton(
        // Pass ref to the navigation method for potential invalidation on return
        onPressed: () => _navigateToFlashcardEdit(context, ref),
        tooltip: 'Add Uncategorized Flashcard',
        child: const Icon(Icons.add),
      ),
    );
  }
}