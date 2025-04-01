// lib/providers/uncategorized_cards_notifier.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/flashcard.dart';
import '../providers/service_providers.dart'; // Access DatabaseHelper provider

// Manually defined AsyncNotifier
class UncategorizedCardsNotifier extends AsyncNotifier<List<Flashcard>> {

  // Fetches the initial list of uncategorized flashcards
  @override
  Future<List<Flashcard>> build() async {
    // 'ref' is automatically available in AsyncNotifier
    final dbHelper = await ref.watch(databaseHelperProvider.future);
    // Fetch flashcards with folderId == null
    return dbHelper.getFlashcards(folderId: null);
  }

  // Action to delete an uncategorized flashcard
  Future<void> deleteCard(int cardId) async {
    // Use ref.read inside methods for one-off reads
    final dbHelper = await ref.read(databaseHelperProvider.future);

    // Set state to loading optimistically while deleting
    state = const AsyncLoading();

    try {
      await dbHelper.deleteFlashcard(cardId);
      // Invalidate provider to refetch the list from DB after successful delete
      ref.invalidateSelf();
      // Ensure the state updates by awaiting the future that resolves after invalidation
      await future;
    } catch (e) {
      print("Error deleting uncategorized flashcard: $e");
      // If an error occurs, set the state back or let invalidateSelf handle refetch
      // Setting state to AsyncError might be better if refetch is not desired on error
      state = AsyncError(e, StackTrace.current);
      // Rethrow to allow UI to potentially display the error
      throw Exception('Failed to delete flashcard: $e');
    }
  }
}

// Manually defined AsyncNotifierProvider
// Note: This is NOT a family provider, as it always fetches the same list (uncategorized)
final uncategorizedCardsNotifierProvider =
    AsyncNotifierProvider<UncategorizedCardsNotifier, List<Flashcard>>(
  () => UncategorizedCardsNotifier(),
);