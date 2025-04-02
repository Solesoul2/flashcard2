// lib/providers/study_notifier.dart
import 'dart:async';
import 'dart:math' show Random, max, min;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For immutable and ValueGetter
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import necessary models, providers, and widgets
import '../models/flashcard.dart';
import '../models/folder.dart';
import '../providers/service_providers.dart';
import '../widgets/interactive_study_card.dart'; // Import for ChecklistItem, color constants
import '../services/database_helper.dart';
import '../services/sr_calculator.dart';
import '../services/persistence_service.dart'; // Needed for checklist state in refreshSingleCard

// --- New Structures for Combined Answer Parsing ---
enum AnswerLineType { text, checklist }

// Represents a single line in the parsed answer, preserving order
@immutable
class ParsedAnswerLine {
  final AnswerLineType type;
  final String textContent; // Content for text lines, or the text part of a checklist item
  final int? originalChecklistIndex; // Links to the ChecklistItem in the state list if type is checklist

  const ParsedAnswerLine({
    required this.type,
    required this.textContent,
    this.originalChecklistIndex,
  });

   @override
   bool operator ==(Object other) =>
       identical(this, other) ||
       other is ParsedAnswerLine &&
           runtimeType == other.runtimeType &&
           type == other.type &&
           textContent == other.textContent &&
           originalChecklistIndex == other.originalChecklistIndex;

   @override
   int get hashCode =>
       type.hashCode ^ textContent.hashCode ^ originalChecklistIndex.hashCode;
}
// --- End New Structures ---


// --- MODIFIED State class definition ---
@immutable
class StudyStateData {
  final List<Flashcard> cards;
  final List<Folder> folderPath;
  // Holds the parsed lines in their original order for rendering
  final List<List<ParsedAnswerLine>> orderedAnswerLinesState;
  // Still holds the checklist items separately for state management (checked status)
  // This list will now be kept sorted (checked items at the bottom) within the notifier.
  final List<List<ChecklistItem>> checklistItemsState;
  final List<bool> answerShownState;
  final int currentPageIndex;
  final Color currentCardRatingColor;
  final bool sessionComplete;
  final int? currentCardLastRatingQuality;

   StudyStateData({
    this.cards = const [],
    this.folderPath = const [],
    this.orderedAnswerLinesState = const [],
    this.checklistItemsState = const [],
    this.answerShownState = const [],
    this.currentPageIndex = 0,
    Color? currentCardRatingColor,
    this.sessionComplete = false,
    this.currentCardLastRatingQuality,
  }) : currentCardRatingColor = currentCardRatingColor ?? InteractiveStudyCard.notRatedColor;

  bool get isCurrentAnswerShown {
     if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < answerShownState.length) { return answerShownState[currentPageIndex]; } return false;
  }
  Flashcard? get currentCard {
      if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < cards.length) { return cards[currentPageIndex]; } return null;
    }

  // Get the ordered lines for the current card
  List<ParsedAnswerLine> get currentOrderedAnswerLines {
     if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < orderedAnswerLinesState.length) {
       return orderedAnswerLinesState[currentPageIndex];
     }
     return [];
  }

   // Get the checklist items state for the current card (already sorted by notifier)
  List<ChecklistItem> get currentChecklistItems {
     if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < checklistItemsState.length) {
       return checklistItemsState[currentPageIndex];
     }
     return [];
  }


  StudyStateData copyWith({
    List<Flashcard>? cards,
    List<Folder>? folderPath,
    List<List<ParsedAnswerLine>>? orderedAnswerLinesState,
    List<List<ChecklistItem>>? checklistItemsState,
    List<bool>? answerShownState,
    int? currentPageIndex,
    Color? currentCardRatingColor,
    bool? sessionComplete,
    ValueGetter<int?>? currentCardLastRatingQuality,
  }) {
    return StudyStateData(
      cards: cards ?? this.cards,
      folderPath: folderPath ?? this.folderPath,
      orderedAnswerLinesState: orderedAnswerLinesState ?? this.orderedAnswerLinesState,
      checklistItemsState: checklistItemsState ?? this.checklistItemsState,
      answerShownState: answerShownState ?? this.answerShownState,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      currentCardRatingColor: currentCardRatingColor ?? this.currentCardRatingColor,
      sessionComplete: sessionComplete ?? this.sessionComplete,
      currentCardLastRatingQuality: currentCardLastRatingQuality != null
          ? currentCardLastRatingQuality()
          : this.currentCardLastRatingQuality,
    );
  }

  // Add == and hashCode for potential state comparison optimizations
   @override
   bool operator ==(Object other) =>
       identical(this, other) ||
       other is StudyStateData &&
           runtimeType == other.runtimeType &&
           listEquals(cards, other.cards) &&
           listEquals(folderPath, other.folderPath) &&
           listEquals(orderedAnswerLinesState, other.orderedAnswerLinesState) && // Requires ParsedAnswerLine equality
           listEquals(checklistItemsState, other.checklistItemsState) && // Requires ChecklistItem equality
           listEquals(answerShownState, other.answerShownState) &&
           currentPageIndex == other.currentPageIndex &&
           currentCardRatingColor == other.currentCardRatingColor &&
           sessionComplete == other.sessionComplete &&
           currentCardLastRatingQuality == other.currentCardLastRatingQuality;

   @override
   int get hashCode =>
       Object.hashAll(cards) ^
       Object.hashAll(folderPath) ^
       Object.hashAll(orderedAnswerLinesState) ^
       Object.hashAll(checklistItemsState) ^
       Object.hashAll(answerShownState) ^
       currentPageIndex.hashCode ^
       currentCardRatingColor.hashCode ^
       sessionComplete.hashCode ^
       currentCardLastRatingQuality.hashCode;
}
// --- End MODIFIED State ---

// --- StudyNotifier ---
class StudyNotifier extends FamilyAsyncNotifier<StudyStateData, int?> {

  final _random = Random();

  // Helper function to sort a list of ChecklistItems (checked items last)
  List<ChecklistItem> _sortChecklist(List<ChecklistItem> items) {
    // Create a mutable copy before sorting
    final sortedItems = List<ChecklistItem>.from(items);
    sortedItems.sort((a, b) {
      if (a.isChecked == b.isChecked) return 0; // Maintain relative order if same status
      return a.isChecked ? 1 : -1; // Checked items go to the end (true > false)
    });
    return sortedItems;
  }

  @override
  Future<StudyStateData> build(int? arg /* folderId */) async {
    final folderId = arg;
    if (folderId == null) {
        print("Warning: StudyNotifier build called with null folderId."); return StudyStateData(sessionComplete: true);
    }

    final dbHelper = await ref.read(databaseHelperProvider.future);
    final persistenceService = await ref.read(persistenceServiceProvider.future);
    List<Flashcard> studySessionCards;
    final now = DateTime.now();

    // Fetching logic remains the same
    print("StudyNotifier Build: Fetching cards for folder $folderId...");
    List<Flashcard> rawFetchedCards = await dbHelper.getDueFlashcards(folderId: folderId, now: now);
    if (rawFetchedCards.isEmpty) {
        print("StudyNotifier Build: No due cards found. Fetching all cards...");
        rawFetchedCards = await dbHelper.getFlashcards(folderId: folderId);
        if (rawFetchedCards.isNotEmpty) {
            // Simple sort by ID for predictability if no due cards
            rawFetchedCards.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
            // More complex sort (e.g., by nextReview, handling nulls)
            // rawFetchedCards.sort((a, b) {
            //    final aIsNull = a.nextReview == null; final bIsNull = b.nextReview == null;
            //    if (aIsNull && !bIsNull) return -1; // Nulls first
            //    if (!aIsNull && bIsNull) return 1;
            //    if (aIsNull && bIsNull) return (a.id ?? 0).compareTo(b.id ?? 0); // If both null, sort by ID
            //    return a.nextReview!.compareTo(b.nextReview!); // Both non-null, compare dates
            // });
        }
    } else {
        // Already sorted by nextReview ASC by getDueFlashcards
    }
    studySessionCards = rawFetchedCards;

    // Log fetched cards
    if (studySessionCards.isNotEmpty) { print("StudyNotifier Build: Fetched ${studySessionCards.length} cards (first few):"); for(int i = 0; i < studySessionCards.length && i < 5; i++) { final q = studySessionCards[i].question; print("  - ID: ${studySessionCards[i].id}, LastQuality: ${studySessionCards[i].lastRatingQuality}, Q_Length: ${q.length}, Question: ${q.replaceAll('\n', '\\n')}"); } }
    else { print("StudyNotifier Build: No cards found for folder $folderId."); }


    if (studySessionCards.isEmpty) {
        print("No cards found for study session in folder $folderId."); final folderPath = await dbHelper.getFolderPath(folderId); return StudyStateData(folderPath: folderPath, sessionComplete: true);
    }

    // --- Parsing and State Initialization ---
    final List<List<ParsedAnswerLine>> allOrderedLines = [];
    final List<List<ChecklistItem>> allChecklistItemsForState = [];
    final List<Map<int, bool>> loadedInitialCheckStates = [];

    for (final card in studySessionCards) {
      final parseResult = _parseAnswerContent(card.answer);
      allOrderedLines.add(parseResult.orderedLines);
      allChecklistItemsForState.add(parseResult.checklistItems);

      if (card.id != null) {
        final initialCheckState = await persistenceService.loadChecklistState(card.id);
        loadedInitialCheckStates.add(initialCheckState);
      } else {
        loadedInitialCheckStates.add({});
      }
    }

    // Apply loaded check states and SORT each card's checklist
    final initialChecklistStateWithPersistence = _applyInitialCheckStates(
      allChecklistItemsForState, loadedInitialCheckStates
    );
    // --- End Parsing ---


    final initialAnswerVisibility = List<bool>.filled(studySessionCards.length, false, growable: true);
    // Use the (potentially sorted) list for initial color calculation
    final initialColor = _calculateRatingColor(initialChecklistStateWithPersistence.isNotEmpty ? initialChecklistStateWithPersistence[0] : []);
    final folderPath = await dbHelper.getFolderPath(folderId);
    final initialLastRatingQuality = studySessionCards.isNotEmpty ? studySessionCards[0].lastRatingQuality : null;
    if(studySessionCards.isNotEmpty) { print("StudyNotifier Build: Setting initial state. First card ID: ${studySessionCards[0].id}, Initial LastQuality: $initialLastRatingQuality"); }

    // Create initial state with the new structure
    return StudyStateData(
      cards: studySessionCards,
      folderPath: folderPath,
      orderedAnswerLinesState: allOrderedLines,
      // Store the SORTED list in the initial state
      checklistItemsState: initialChecklistStateWithPersistence,
      answerShownState: initialAnswerVisibility,
      currentPageIndex: 0,
      currentCardRatingColor: initialColor,
      sessionComplete: false,
      currentCardLastRatingQuality: initialLastRatingQuality,
    );
  }

  // _parseAnswerContent remains the same
  ({ List<ParsedAnswerLine> orderedLines, List<ChecklistItem> checklistItems }) _parseAnswerContent(String answer) {
    final lines = answer.split('\n');
    final List<ParsedAnswerLine> ordered = [];
    final List<ChecklistItem> items = [];
    int checklistIndex = 0;

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('* ')) {
        final itemText = trimmedLine.substring(2).trim();
        final checklistItem = ChecklistItem(
          originalIndex: checklistIndex,
          text: itemText,
          isChecked: false,
        );
        items.add(checklistItem);
        ordered.add(ParsedAnswerLine(
          type: AnswerLineType.checklist,
          textContent: itemText,
          originalChecklistIndex: checklistIndex,
        ));
        checklistIndex++;
      } else {
        ordered.add(ParsedAnswerLine(
          type: AnswerLineType.text,
          textContent: line, // Keep original line for non-checklist items
          originalChecklistIndex: null,
        ));
      }
    }
    return (orderedLines: ordered, checklistItems: items);
   }

  // *** MODIFIED: _applyInitialCheckStates ***
  // Applies persisted check states AND sorts the list for each card
  List<List<ChecklistItem>> _applyInitialCheckStates(
      List<List<ChecklistItem>> allChecklistItems,
      List<Map<int, bool>> loadedCheckStates
      ) {
     List<List<ChecklistItem>> statefulChecklists = [];
     for(int i = 0; i < allChecklistItems.length; i++) {
         final cardItems = allChecklistItems[i];
         final cardInitialCheckState = (i < loadedCheckStates.length) ? loadedCheckStates[i] : <int, bool>{};
         List<ChecklistItem> itemsWithState = [];
         for(final item in cardItems) {
           itemsWithState.add(item.copyWith(
             isChecked: cardInitialCheckState[item.originalIndex] ?? item.isChecked
           ));
         }
         // Sort the list for this card after applying persisted state
         statefulChecklists.add(_sortChecklist(itemsWithState));
     }
     return statefulChecklists;
   }

  // _calculateRatingColor remains the same
  Color _calculateRatingColor(List<ChecklistItem> checklistItems) { if (checklistItems.isEmpty || !checklistItems.any((item) => item.isChecked)) { return InteractiveStudyCard.notRatedColor; } final totalItems = checklistItems.length; final checkedItems = checklistItems.where((item) => item.isChecked).length; final percentage = totalItems > 0 ? checkedItems / totalItems : 0.0; const List<Color> gradientColors = [ InteractiveStudyCard.zeroScoreColor, Colors.orange, Colors.amber, Color(0xFF66BB6A), Colors.blue ]; const List<double> gradientStops = [ 0.0, 0.25, 0.5, 0.75, 1.0 ]; final clampedPercentage = percentage.clamp(0.0, 1.0); for (int i = 0; i < gradientStops.length - 1; i++) { final stop1 = gradientStops[i]; final stop2 = gradientStops[i + 1]; if (clampedPercentage >= stop1 && clampedPercentage <= stop2) { final range = stop2 - stop1; final t = range == 0.0 ? 0.0 : (clampedPercentage - stop1) / range; return Color.lerp(gradientColors[i], gradientColors[i + 1], t) ?? gradientColors.last; } } return gradientColors.last; }

  // *** MODIFIED: _advanceSession ***
  void _advanceSession(StudyStateData currentState, int reviewedCardIndex) {
     if (currentState.sessionComplete) return;
     final updatedSessionCards = List<Flashcard>.from(currentState.cards);
     final updatedOrderedLines = List<List<ParsedAnswerLine>>.from(currentState.orderedAnswerLinesState);
     final updatedChecklistItems = List<List<ChecklistItem>>.from(currentState.checklistItemsState);
     final updatedAnswerShown = List<bool>.from(currentState.answerShownState);

     if (reviewedCardIndex >= 0 && reviewedCardIndex < updatedSessionCards.length) {
       updatedSessionCards.removeAt(reviewedCardIndex);
       updatedOrderedLines.removeAt(reviewedCardIndex);
       updatedChecklistItems.removeAt(reviewedCardIndex); // Remove the SORTED list for this card
       updatedAnswerShown.removeAt(reviewedCardIndex);
       print("_advanceSession: Removed card at index $reviewedCardIndex from session queue.");
     } else { print("Warning: Invalid index $reviewedCardIndex provided to _advanceSession."); }

     if (updatedSessionCards.isEmpty) {
        print("_advanceSession: Study session queue empty. Marking session complete.");
        state = AsyncData(currentState.copyWith(
            cards: [], orderedAnswerLinesState: [], checklistItemsState: [],
            answerShownState: [], currentPageIndex: 0, sessionComplete: true,
            currentCardLastRatingQuality: () => null ));
        return;
     }

     // Determine the next index. Usually stays the same after removal,
     // unless the removed item was the last one.
     int nextIndex = reviewedCardIndex;
     if (nextIndex >= updatedSessionCards.length) {
         // If the removed card was the last one, wrap around to the start
         nextIndex = 0;
     }
     // If it wasn't the last one, the element originally *after* the removed one
     // is now at the `reviewedCardIndex`, so `nextIndex` remains correct.


     print("_advanceSession: Next index will be $nextIndex");
     // Pass the state containing the removed card's data
     _updateStateForNewIndex(
         currentState.copyWith(
             cards: updatedSessionCards,
             orderedAnswerLinesState: updatedOrderedLines,
             checklistItemsState: updatedChecklistItems, // Pass the list with removed card
             answerShownState: updatedAnswerShown
         ),
         nextIndex
     );
  }

  // *** MODIFIED: Helper to update state for the new current card index ***
  void _updateStateForNewIndex(StudyStateData currentState, int newIndex) {
     if (currentState.sessionComplete) return;
     if (newIndex < 0 || newIndex >= currentState.cards.length) { print("Warning: Attempted state update for invalid newIndex $newIndex..."); state = AsyncData(currentState.copyWith(sessionComplete: true, currentCardLastRatingQuality: () => null)); return; }

     final newAnswerState = List<bool>.from(currentState.answerShownState);
     // Always set the answer visibility to false for the new card
     if (newIndex < newAnswerState.length) {
        newAnswerState[newIndex] = false;
     } else {
         print("Warning: Answer state list length mismatch in _updateStateForNewIndex. Length: ${newAnswerState.length}, Index: $newIndex");
         // Attempt to recover if possible, e.g., add missing entries? Or just log.
         // For simplicity, just log for now.
     }


     // Get the checklist items STATE for the new card (already sorted)
     final currentCardChecklistState = (newIndex >= 0 && newIndex < currentState.checklistItemsState.length)
         ? currentState.checklistItemsState[newIndex] : <ChecklistItem>[];
     final newRatingColor = _calculateRatingColor(currentCardChecklistState);

     final newLastRatingQuality = currentState.cards[newIndex].lastRatingQuality;
     print("_updateStateForNewIndex: Updating state for index $newIndex. Card ID: ${currentState.cards[newIndex].id}, LastQuality from state list: $newLastRatingQuality");

     state = AsyncData(currentState.copyWith(
         currentPageIndex: newIndex,
         answerShownState: newAnswerState,
         // checklistItemsState is already updated/sorted from build or advanceSession
         currentCardRatingColor: newRatingColor,
         currentCardLastRatingQuality: () => newLastRatingQuality,
         sessionComplete: false
     ));
  }

  // toggleAnswerVisibility remains the same
  void toggleAnswerVisibility() { state.whenData((data) { if (!data.sessionComplete && data.cards.isNotEmpty && data.currentPageIndex >= 0 && data.currentPageIndex < data.answerShownState.length) { final newAnswerState = List<bool>.from(data.answerShownState); newAnswerState[data.currentPageIndex] = !newAnswerState[data.currentPageIndex]; state = AsyncData(data.copyWith(answerShownState: newAnswerState)); } }); }

  // *** MODIFIED: handleChecklistChanged ***
  Future<void> handleChecklistChanged(int itemOriginalIndex, bool isChecked) async {
     final currentDataAsync = state;
     if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return;
     final data = currentDataAsync.value!;
     final currentIndex = data.currentPageIndex; // Store current index

      if (currentIndex < 0 || currentIndex >= data.checklistItemsState.length) {
          print("Error: Invalid currentPageIndex $currentIndex in handleChecklistChanged.");
          return;
      }


     // Create a deep copy of the outer list and the relevant inner list
     final newChecklistItemsStateList = List<List<ChecklistItem>>.from(
         data.checklistItemsState.map((list) => List<ChecklistItem>.from(list.map((item) => item.copyWith())))
     );
     final currentCardChecklistStateMutable = newChecklistItemsStateList[currentIndex];
     final itemIndexInState = currentCardChecklistStateMutable.indexWhere((item) => item.originalIndex == itemOriginalIndex);

     if (itemIndexInState == -1) {
         print("Error: Checklist item state with originalIndex $itemOriginalIndex not found for card at index $currentIndex.");
         return;
     }

     // Update the isChecked status
     currentCardChecklistStateMutable[itemIndexInState] = currentCardChecklistStateMutable[itemIndexInState].copyWith(isChecked: isChecked);

     // *** Re-sort the checklist for the current card ***
     final sortedCurrentCardChecklist = _sortChecklist(currentCardChecklistStateMutable);
     // Replace the old list for this card with the newly sorted one
     newChecklistItemsStateList[currentIndex] = sortedCurrentCardChecklist;

     // Persist the state using the updated (but before sorting) map
     final cardId = data.currentCard?.id;
     if (cardId != null) {
       final Map<int, bool> stateToSave = {
         // Build map from the potentially unsorted mutable list *before* sorting,
         // as persistence expects originalIndex -> isChecked
         for (var item in currentCardChecklistStateMutable) item.originalIndex: item.isChecked
       };
       try {
         final persistenceService = await ref.read(persistenceServiceProvider.future);
         await persistenceService.saveChecklistState(cardId, stateToSave);
       } catch (e) { print("Error saving checklist state for card $cardId: $e"); }
     }

     // Recalculate rating color based on the UPDATED state list
     final newRatingColor = _calculateRatingColor(sortedCurrentCardChecklist); // Use sorted list for color

     // Update the main state with the SORTED list and new color
     state = AsyncData(data.copyWith(
         checklistItemsState: newChecklistItemsStateList, // Store the list containing the sorted sublist
         currentCardRatingColor: newRatingColor
     ));
  }


  // updateRatingColor remains the same
  void updateRatingColor(int? reportingCardId, Color color) { state.whenData((data) { if (data.sessionComplete) return; final currentCard = data.currentCard; final expectedCardId = currentCard?.id; if (reportingCardId != null && expectedCardId != null && reportingCardId == expectedCardId && data.currentCardRatingColor != color) { final Color colorToSet = (color == const Color(0xFFbdbdbd)) ? InteractiveStudyCard.notRatedColor : color; state = AsyncData(data.copyWith(currentCardRatingColor: colorToSet)); } }); }

  // skipCard remains the same
   void skipCard() { state.whenData((data) { if (data.sessionComplete) return; final currentIndex = data.currentPageIndex; final cardId = data.currentCard?.id; print("Skipping card index: $currentIndex (ID: $cardId)"); _advanceSession(data, currentIndex); }); }


  // *** MODIFIED: rateCard ***
  Future<void> rateCard() async {
      final currentDataAsync = state;
      if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return;
      final data = currentDataAsync.value!;
      final currentCard = data.currentCard;
      final currentIndex = data.currentPageIndex;

      if (currentCard?.id == null) { print("Error: Cannot rate card without an ID. Skipping."); _advanceSession(data, currentIndex); return; }
      final cardId = currentCard!.id!;

      // Quality calculation uses the currentChecklistItems getter (which returns the sorted list)
      int quality;
      final currentCardChecklistStateItems = data.currentChecklistItems; // Already sorted
      if (currentCardChecklistStateItems.isEmpty) { quality = 3; print("Rating card ID $cardId (no checklist items in state): Default Quality=$quality");
      } else {
          final totalItems = currentCardChecklistStateItems.length;
          final checkedItems = currentCardChecklistStateItems.where((item) => item.isChecked).length;
          final percentage = totalItems > 0 ? (checkedItems / totalItems) : 0.0;
          if (percentage == 1.0) { quality = 5; } else if (percentage >= 0.8) { quality = 4; } else if (percentage >= 0.5) { quality = 3; } else if (percentage >= 0.2) { quality = 2; } else if (percentage > 0) { quality = 1; } else { quality = 0; }
          print("Rating card ID $cardId (checklist state ${checkedItems}/${totalItems} = ${percentage.toStringAsFixed(2)}): Calculated Quality=$quality");
      }

      // SR Calculation remains the same
      final SRResult srResult = SRCalculator.calculate( quality: quality, previousEasinessFactor: currentCard.easinessFactor, previousInterval: currentCard.interval, previousRepetitions: currentCard.repetitions );
      DateTime now = DateTime.now(); int calculatedIntervalDays = max(0, srResult.interval); DateTime nextReviewDate = now.add(Duration(days: calculatedIntervalDays)).add(const Duration(seconds: 1)); // Add 1 sec to ensure it's after 'now'

      // Persist and Update State
      try {
          final dbHelper = await ref.read(databaseHelperProvider.future);
          await dbHelper.updateFlashcardReviewData( cardId, easinessFactor: srResult.easinessFactor, interval: srResult.interval, repetitions: srResult.repetitions, lastReviewed: now, nextReview: nextReviewDate, lastRatingQuality: quality );
          print("  Successfully persisted SR data & Last Quality ($quality) for card ID $cardId: $srResult, Next Review: ${nextReviewDate.toIso8601String()}");

          // Important: Update the card within the *current state* before advancing
          final updatedCards = List<Flashcard>.from(data.cards);
          final cardIndexInList = updatedCards.indexWhere((c) => c.id == cardId);
          if (cardIndexInList != -1) {
              Flashcard originalCardFromState = updatedCards[cardIndexInList];
              // Create the updated card object reflecting the new SR data AND the last rating quality
              Flashcard cardJustRated = originalCardFromState.copyWith(
                  easinessFactor: srResult.easinessFactor,
                  interval: srResult.interval,
                  repetitions: srResult.repetitions,
                  lastReviewed: () => now,
                  nextReview: () => nextReviewDate,
                  lastRatingQuality: () => quality // Make sure this is updated
              );
              // Place the updated card back into the list
              updatedCards[cardIndexInList] = cardJustRated;

              // Advance the session using the state that contains the updated card
              _advanceSession(data.copyWith(cards: updatedCards), currentIndex);
          } else {
              print("Warning: Rated card $cardId not found in current session list after DB update. Advancing without state update.");
              _advanceSession(data, currentIndex);
          }
      } catch (e) { print("Error persisting SR data for card ID $cardId: $e"); _advanceSession(data, currentIndex); }
   }


   // deleteCard remains the same
   Future<void> deleteCard(Flashcard cardToDelete) async { if (cardToDelete.id == null) return; final currentDataAsync = state; if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return; final data = currentDataAsync.value!; final cardIndexInList = data.cards.indexWhere((c) => c.id == cardToDelete.id); try { final dbHelper = await ref.read(databaseHelperProvider.future); await dbHelper.deleteFlashcard(cardToDelete.id!); print("Deleted card ID ${cardToDelete.id} from database."); if (cardIndexInList != -1) { _advanceSession(data, cardIndexInList); } else { print("Deleted card was not in list, refreshing study state."); ref.invalidateSelf(); await future; } } catch (e) { print("Error deleting card ID ${cardToDelete.id}: $e"); throw Exception("Error deleting flashcard: $e"); } }

  // *** ADDED: Method to refresh a single card's data ***
  Future<void> refreshSingleCard(int cardId) async {
    final currentDataAsync = state;
    // Ensure we have valid data before proceeding
    if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) {
        print("StudyNotifier: Cannot refresh single card, state is invalid or session complete.");
        return;
    }
    final data = currentDataAsync.value!;

    print("StudyNotifier: Refreshing single card ID: $cardId");

    try {
      final dbHelper = await ref.read(databaseHelperProvider.future);
      final persistenceService = await ref.read(persistenceServiceProvider.future); // Needed for checklist state

      // Fetch the latest card data from the database
      final List<Map<String, dynamic>> maps = await (await dbHelper.database).query(
         DatabaseHelper.flashcardsTable, // Use constant
         columns: [ // Explicitly list all columns needed by Flashcard.fromMap
           'id', 'question', 'answer', 'folderId',
           'easinessFactor', 'interval', 'repetitions',
           'lastReviewed', 'nextReview', 'lastRatingQuality'
         ],
         where: 'id = ?', // Use actual column name 'id'
         whereArgs: [cardId],
         limit: 1,
      );

      if (maps.isEmpty) {
        print("  > Card ID $cardId not found in DB during refresh. Maybe deleted during edit?");
        // If card was somehow deleted, invalidate the whole provider to remove it
        ref.invalidateSelf();
        await future;
        return;
      }

      final updatedCard = Flashcard.fromMap(maps.first);
      print("  > Fetched updated card data. Question: '${updatedCard.question.substring(0, min(updatedCard.question.length, 50)).replaceAll('\n', '\\n')}...'");

      // Find the index of this card within the current session's list
      final indexInState = data.cards.indexWhere((card) => card.id == cardId);

      if (indexInState == -1) {
        print("  > Card ID $cardId not found in current session state list (length ${data.cards.length}). Perhaps list changed? Invalidating.");
        // This shouldn't normally happen if the edit was on a card in the current session.
        // Invalidate as a fallback.
         ref.invalidateSelf();
         await future;
        return;
      }

      print("  > Card found at index $indexInState in current state list.");

      // Create mutable copies of the state lists to modify safely
      final updatedCardsList = List<Flashcard>.from(data.cards);
      final updatedOrderedLinesList = List<List<ParsedAnswerLine>>.from(data.orderedAnswerLinesState);
      final updatedChecklistItemsList = List<List<ChecklistItem>>.from(data.checklistItemsState); // This list contains sorted sublists

      // --- Update the state lists at the specific index ---

      // 1. Update the Flashcard object
      updatedCardsList[indexInState] = updatedCard;

      // 2. Re-parse the updated answer content
      final parseResult = _parseAnswerContent(updatedCard.answer);

      // 3. Update the ordered lines list
      updatedOrderedLinesList[indexInState] = parseResult.orderedLines;

      // 4. Update the checklist items state list
      //    a. Load persisted checklist state for the updated card
      final persistedCheckState = await persistenceService.loadChecklistState(cardId);
      //    b. Apply persisted state to the newly parsed checklist items
      List<ChecklistItem> itemsWithState = [];
       for(final item in parseResult.checklistItems) {
         itemsWithState.add(item.copyWith(
           isChecked: persistedCheckState[item.originalIndex] ?? item.isChecked
         ));
       }
      //    c. Sort the checklist items for this card after applying state
      //    d. Update the list in our state copy
      updatedChecklistItemsList[indexInState] = _sortChecklist(itemsWithState);

      print("  > Updated card, ordered lines, and checklist state at index $indexInState.");

      // Update the main state using AsyncData.
      // Crucially, keep the currentPageIndex the same.
      // Also keep answerShownState, sessionComplete status the same.
      state = AsyncData(data.copyWith(
        cards: updatedCardsList,
        orderedAnswerLinesState: updatedOrderedLinesList,
        checklistItemsState: updatedChecklistItemsList,
        // Explicitly DO NOT change these:
        // currentPageIndex: data.currentPageIndex,
        // answerShownState: data.answerShownState,
        // sessionComplete: data.sessionComplete,
        // currentCardRatingColor: data.currentCardRatingColor, // Let UI handle updates based on new data
        // currentCardLastRatingQuality: () => updatedCard.lastRatingQuality, // Update this based on fetched data
      ));
       print("StudyNotifier: Single card refresh complete for ID: $cardId. State updated.");

    } catch (e, stackTrace) {
      print("Error refreshing single card ID $cardId: $e\n$stackTrace");
      // Optionally set error state or re-invalidate on error
      state = AsyncError(e, stackTrace);
    }
  }
  // *** END ADDED METHOD ***
}

// Provider Definition remains the same
final studyProvider = AsyncNotifierProvider.family<StudyNotifier, StudyStateData, int?>(
  () => StudyNotifier(),
);