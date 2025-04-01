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
  final List<List<ChecklistItem>> checklistItemsState;
  // No longer storing separate answerMarkdownState
  // final List<String> answerMarkdownState; // REMOVED
  final List<bool> answerShownState;
  final int currentPageIndex;
  final Color currentCardRatingColor;
  final bool sessionComplete;
  final int? currentCardLastRatingQuality;

   StudyStateData({
    this.cards = const [],
    this.folderPath = const [],
    this.orderedAnswerLinesState = const [], // ADDED
    this.checklistItemsState = const [], // Keep for state
    // this.answerMarkdownState = const [], // REMOVED
    this.answerShownState = const [],
    this.currentPageIndex = 0,
    Color? currentCardRatingColor,
    this.sessionComplete = false,
    this.currentCardLastRatingQuality,
  }) : currentCardRatingColor = currentCardRatingColor ?? InteractiveStudyCard.notRatedColor;

  bool get isCurrentAnswerShown { /* ... remains same ... */
     if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < answerShownState.length) { return answerShownState[currentPageIndex]; } return false;
  }
  Flashcard? get currentCard { /* ... remains same ... */
      if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < cards.length) { return cards[currentPageIndex]; } return null;
    }

  // Get the ordered lines for the current card
  List<ParsedAnswerLine> get currentOrderedAnswerLines {
     if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < orderedAnswerLinesState.length) {
       return orderedAnswerLinesState[currentPageIndex];
     }
     return [];
  }

   // Get the checklist items state for the current card
  List<ChecklistItem> get currentChecklistItems {
     if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < checklistItemsState.length) {
       return checklistItemsState[currentPageIndex];
     }
     return [];
  }


  StudyStateData copyWith({
    List<Flashcard>? cards,
    List<Folder>? folderPath,
    List<List<ParsedAnswerLine>>? orderedAnswerLinesState, // ADDED
    List<List<ChecklistItem>>? checklistItemsState, // Keep for state
    // List<String>? answerMarkdownState, // REMOVED
    List<bool>? answerShownState,
    int? currentPageIndex,
    Color? currentCardRatingColor,
    bool? sessionComplete,
    ValueGetter<int?>? currentCardLastRatingQuality,
  }) {
    return StudyStateData(
      cards: cards ?? this.cards,
      folderPath: folderPath ?? this.folderPath,
      orderedAnswerLinesState: orderedAnswerLinesState ?? this.orderedAnswerLinesState, // ADDED
      checklistItemsState: checklistItemsState ?? this.checklistItemsState, // Keep for state
      // answerMarkdownState: answerMarkdownState ?? this.answerMarkdownState, // REMOVED
      answerShownState: answerShownState ?? this.answerShownState,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      currentCardRatingColor: currentCardRatingColor ?? this.currentCardRatingColor,
      sessionComplete: sessionComplete ?? this.sessionComplete,
      currentCardLastRatingQuality: currentCardLastRatingQuality != null
          ? currentCardLastRatingQuality()
          : this.currentCardLastRatingQuality,
    );
  }
}
// --- End MODIFIED State ---

// --- StudyNotifier ---
class StudyNotifier extends FamilyAsyncNotifier<StudyStateData, int?> {

  final _random = Random();

  // *** MODIFIED: build method ***
  @override
  Future<StudyStateData> build(int? arg /* folderId */) async {
    final folderId = arg;
    if (folderId == null) { /* ... handle null folderId ... */
        print("Warning: StudyNotifier build called with null folderId."); return StudyStateData(sessionComplete: true);
    }

    final dbHelper = await ref.read(databaseHelperProvider.future);
    final persistenceService = await ref.read(persistenceServiceProvider.future);
    List<Flashcard> studySessionCards;
    final now = DateTime.now();

    // Fetching logic remains the same
    print("StudyNotifier Build: Fetching cards for folder $folderId...");
    List<Flashcard> rawFetchedCards = await dbHelper.getDueFlashcards(folderId: folderId, now: now);
    if (rawFetchedCards.isEmpty) { /* ... fetch all if no due cards ... */
        print("StudyNotifier Build: No due cards found. Fetching all cards...");
        rawFetchedCards = await dbHelper.getFlashcards(folderId: folderId);
        if (rawFetchedCards.isNotEmpty) { rawFetchedCards.sort((a, b) { /* ... sorting ... */ final aIsNull = a.nextReview == null; final bIsNull = b.nextReview == null; if (aIsNull && !bIsNull) return -1; if (!aIsNull && bIsNull) return 1; if (aIsNull && bIsNull) return 0; if (a.nextReview == null || b.nextReview == null) return 0; return a.nextReview!.compareTo(b.nextReview!); }); }
    }
    studySessionCards = rawFetchedCards;

    // Log fetched cards (using updated log format)
     if (studySessionCards.isNotEmpty) { print("StudyNotifier Build: Fetched ${studySessionCards.length} cards (first few):"); for(int i = 0; i < studySessionCards.length && i < 5; i++) { final q = studySessionCards[i].question; print("  - ID: ${studySessionCards[i].id}, LastQuality: ${studySessionCards[i].lastRatingQuality}, Q_Length: ${q.length}, Question: ${q.replaceAll('\n', '\\n')}"); } }
     else { print("StudyNotifier Build: No cards found for folder $folderId."); }


    if (studySessionCards.isEmpty) { /* ... handle no cards ... */
        print("No cards found for study session in folder $folderId."); final folderPath = await dbHelper.getFolderPath(folderId); return StudyStateData(folderPath: folderPath, sessionComplete: true);
    }

    // --- MODIFIED Parsing and State Initialization ---
    final List<List<ParsedAnswerLine>> allOrderedLines = [];
    final List<List<ChecklistItem>> allChecklistItemsForState = [];
    final List<Map<int, bool>> loadedInitialCheckStates = [];

    for (final card in studySessionCards) {
      // Parse into the new combined list structure AND separate checklist items
      final parseResult = _parseAnswerContent(card.answer);
      allOrderedLines.add(parseResult.orderedLines);
      allChecklistItemsForState.add(parseResult.checklistItems); // Keep for state mgmt

      // Load persisted check states
      if (card.id != null) {
        final initialCheckState = await persistenceService.loadChecklistState(card.id);
        loadedInitialCheckStates.add(initialCheckState);
      } else {
        loadedInitialCheckStates.add({});
      }
    }

    // Apply loaded check states to the checklist items used for state management
    final initialChecklistStateWithPersistence = _applyInitialCheckStates(
      allChecklistItemsForState, loadedInitialCheckStates
    );
    // --- End MODIFIED Parsing ---


    final initialAnswerVisibility = List<bool>.filled(studySessionCards.length, false, growable: true);
    final initialColor = _calculateRatingColor(initialChecklistStateWithPersistence.isNotEmpty ? initialChecklistStateWithPersistence[0] : []);
    final folderPath = await dbHelper.getFolderPath(folderId);
    final initialLastRatingQuality = studySessionCards.isNotEmpty ? studySessionCards[0].lastRatingQuality : null;
    if(studySessionCards.isNotEmpty) { print("StudyNotifier Build: Setting initial state. First card ID: ${studySessionCards[0].id}, Initial LastQuality: $initialLastRatingQuality"); }

    // Create initial state with the new structure
    return StudyStateData(
      cards: studySessionCards,
      folderPath: folderPath,
      orderedAnswerLinesState: allOrderedLines, // Use new combined list
      checklistItemsState: initialChecklistStateWithPersistence, // Use state list with loaded checks
      answerShownState: initialAnswerVisibility,
      currentPageIndex: 0,
      currentCardRatingColor: initialColor,
      sessionComplete: false,
      currentCardLastRatingQuality: initialLastRatingQuality,
    );
  }

  // *** MODIFIED: _parseAnswerContent ***
  // Now returns the ordered list and the separate checklist items for state
  ({ List<ParsedAnswerLine> orderedLines, List<ChecklistItem> checklistItems }) _parseAnswerContent(String answer) {
    final lines = answer.split('\n');
    final List<ParsedAnswerLine> ordered = [];
    final List<ChecklistItem> items = [];
    int checklistIndex = 0; // This is the index within the checklistItems list

    for (final line in lines) {
      // Check if line starts with "* " AFTER trimming whitespace
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('* ')) {
        final itemText = trimmedLine.substring(2).trim(); // Get text after "* "
        // Create the ChecklistItem for state management
        final checklistItem = ChecklistItem(
          originalIndex: checklistIndex, // Store its index within the checklistItems list
          text: itemText,
          isChecked: false, // Initial state, will be overridden by persistence
        );
        items.add(checklistItem);
        // Add to the ordered list for rendering, linking via originalChecklistIndex
        ordered.add(ParsedAnswerLine(
          type: AnswerLineType.checklist,
          textContent: itemText, // Store text here too for convenience if needed
          originalChecklistIndex: checklistIndex,
        ));
        checklistIndex++; // Increment index for the next checklist item
      } else {
        // Add regular text line to the ordered list
        ordered.add(ParsedAnswerLine(
          type: AnswerLineType.text,
          textContent: line, // Keep original line for rendering markdown
          originalChecklistIndex: null,
        ));
      }
    }
    return (orderedLines: ordered, checklistItems: items);
   }

  // *** RENAMED and MODIFIED: _applyInitialCheckStates ***
  // Applies persisted check states to the separate checklist item state list
  List<List<ChecklistItem>> _applyInitialCheckStates(
      List<List<ChecklistItem>> allChecklistItems, // The items parsed from content
      List<Map<int, bool>> loadedCheckStates // The states loaded from persistence
      ) {
     List<List<ChecklistItem>> statefulChecklists = [];
     for(int i = 0; i < allChecklistItems.length; i++) {
         final cardItems = allChecklistItems[i]; // Items for this card
         // Get the persisted state map {originalIndex: isChecked} for this card
         final cardInitialCheckState = (i < loadedCheckStates.length) ? loadedCheckStates[i] : <int, bool>{};
         List<ChecklistItem> itemsWithState = [];
         // Iterate through the items parsed for this card
         for(final item in cardItems) {
           // Create a new ChecklistItem using the persisted check state or default false
           itemsWithState.add(item.copyWith(
             isChecked: cardInitialCheckState[item.originalIndex] ?? item.isChecked
           ));
         }
         statefulChecklists.add(itemsWithState);
     }
     return statefulChecklists;
   }

  // _calculateRatingColor remains the same, takes List<ChecklistItem>
  Color _calculateRatingColor(List<ChecklistItem> checklistItems) { /* ... */ if (checklistItems.isEmpty || !checklistItems.any((item) => item.isChecked)) { return InteractiveStudyCard.notRatedColor; } final totalItems = checklistItems.length; final checkedItems = checklistItems.where((item) => item.isChecked).length; final percentage = totalItems > 0 ? checkedItems / totalItems : 0.0; const List<Color> gradientColors = [ InteractiveStudyCard.zeroScoreColor, Colors.orange, Colors.amber, Color(0xFF66BB6A), Colors.blue ]; const List<double> gradientStops = [ 0.0, 0.25, 0.5, 0.75, 1.0 ]; final clampedPercentage = percentage.clamp(0.0, 1.0); for (int i = 0; i < gradientStops.length - 1; i++) { final stop1 = gradientStops[i]; final stop2 = gradientStops[i + 1]; if (clampedPercentage >= stop1 && clampedPercentage <= stop2) { final range = stop2 - stop1; final t = range == 0.0 ? 0.0 : (clampedPercentage - stop1) / range; return Color.lerp(gradientColors[i], gradientColors[i + 1], t) ?? gradientColors.last; } } return gradientColors.last; }

  // *** MODIFIED: Helper to advance session ***
  void _advanceSession(StudyStateData currentState, int reviewedCardIndex) {
     if (currentState.sessionComplete) return;
     // Make copies of state lists
     final updatedSessionCards = List<Flashcard>.from(currentState.cards);
     final updatedOrderedLines = List<List<ParsedAnswerLine>>.from(currentState.orderedAnswerLinesState); // Copy new list
     final updatedChecklistItems = List<List<ChecklistItem>>.from(currentState.checklistItemsState); // Copy state list
     final updatedAnswerShown = List<bool>.from(currentState.answerShownState);

     // Remove the reviewed card from all lists
     if (reviewedCardIndex >= 0 && reviewedCardIndex < updatedSessionCards.length) {
       updatedSessionCards.removeAt(reviewedCardIndex);
       updatedOrderedLines.removeAt(reviewedCardIndex); // Remove from new list
       updatedChecklistItems.removeAt(reviewedCardIndex); // Remove from state list
       updatedAnswerShown.removeAt(reviewedCardIndex);
       print("_advanceSession: Removed card at index $reviewedCardIndex from session queue.");
     } else { print("Warning: Invalid index $reviewedCardIndex provided to _advanceSession."); }

     // Check if session is complete
     if (updatedSessionCards.isEmpty) {
        print("_advanceSession: Study session queue empty. Marking session complete.");
        state = AsyncData(currentState.copyWith(
            cards: [],
            orderedAnswerLinesState: [], // Clear new list
            checklistItemsState: [], // Clear state list
            answerShownState: [],
            currentPageIndex: 0, sessionComplete: true, currentCardLastRatingQuality: () => null ));
        return;
     }

     // Determine next index
     int nextIndex = reviewedCardIndex;
     if (nextIndex >= updatedSessionCards.length) { nextIndex = 0; }

     print("_advanceSession: Next index will be $nextIndex");
     // Update state using the modified lists
     _updateStateForNewIndex(
         currentState.copyWith(
             cards: updatedSessionCards,
             orderedAnswerLinesState: updatedOrderedLines, // Pass new list
             checklistItemsState: updatedChecklistItems, // Pass state list
             answerShownState: updatedAnswerShown
         ),
         nextIndex
     );
  }

  // *** MODIFIED: Helper to update state for the new current card index ***
  void _updateStateForNewIndex(StudyStateData currentState, int newIndex) {
     if (currentState.sessionComplete) return;
     if (newIndex < 0 || newIndex >= currentState.cards.length) { /* ... handle invalid index ... */ print("Warning: Attempted state update for invalid newIndex $newIndex..."); state = AsyncData(currentState.copyWith(sessionComplete: true, currentCardLastRatingQuality: () => null)); return; }

     // Reset answer shown state for the new card
     final newAnswerState = List<bool>.from(currentState.answerShownState);
     if (newIndex < newAnswerState.length) { newAnswerState[newIndex] = false; }
     else { print("Warning: Answer state list length mismatch in _updateStateForNewIndex."); }

     // Get the checklist items STATE for the new card to calculate color
     final currentCardChecklistState = (newIndex >= 0 && newIndex < currentState.checklistItemsState.length)
         ? currentState.checklistItemsState[newIndex] : <ChecklistItem>[];
     final newRatingColor = _calculateRatingColor(currentCardChecklistState); // Use state list for color calc

     // Get last rating quality from the Flashcard object
     final newLastRatingQuality = currentState.cards[newIndex].lastRatingQuality;
     print("_updateStateForNewIndex: Updating state for index $newIndex. Card ID: ${currentState.cards[newIndex].id}, LastQuality from state list: $newLastRatingQuality");

     // Update the overall state
     state = AsyncData(currentState.copyWith(
         currentPageIndex: newIndex,
         answerShownState: newAnswerState,
         currentCardRatingColor: newRatingColor,
         currentCardLastRatingQuality: () => newLastRatingQuality,
         sessionComplete: false
     ));
  }

  // --- Public Methods to Modify State ---

  // toggleAnswerVisibility remains the same
  void toggleAnswerVisibility() { /* ... */ state.whenData((data) { if (!data.sessionComplete && data.cards.isNotEmpty && data.currentPageIndex >= 0 && data.currentPageIndex < data.answerShownState.length) { final newAnswerState = List<bool>.from(data.answerShownState); newAnswerState[data.currentPageIndex] = !newAnswerState[data.currentPageIndex]; state = AsyncData(data.copyWith(answerShownState: newAnswerState)); } }); }

  // *** MODIFIED: handleChecklistChanged ***
  // Updates the CHECKLIST ITEM STATE list
  Future<void> handleChecklistChanged(int itemOriginalIndex, bool isChecked) async {
     final currentDataAsync = state;
     if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return;
     final data = currentDataAsync.value!;
     // Check index against the checklistItemsState list
     if (data.currentPageIndex < 0 || data.currentPageIndex >= data.checklistItemsState.length) {
         print("Error: Invalid currentPageIndex ${data.currentPageIndex} in handleChecklistChanged.");
         return;
     }

     // --- Modify the checklistItemsState list ---
     // Create a deep copy of the outer list and the relevant inner list
     final newChecklistItemsStateList = List<List<ChecklistItem>>.from(
         data.checklistItemsState.map((list) => List<ChecklistItem>.from(list.map((item) => item.copyWith())))
     );
     final currentCardChecklistStateMutable = newChecklistItemsStateList[data.currentPageIndex];
     // Find the item by its originalIndex within this card's state list
     final itemIndexInState = currentCardChecklistStateMutable.indexWhere((item) => item.originalIndex == itemOriginalIndex);

     if (itemIndexInState == -1) {
         print("Error: Checklist item state with originalIndex $itemOriginalIndex not found.");
         return;
     }
     // Update the isChecked status in the copied state list
     currentCardChecklistStateMutable[itemIndexInState] = currentCardChecklistStateMutable[itemIndexInState].copyWith(isChecked: isChecked);
     // --- End modification of checklistItemsState ---


     // Persist the updated check state using the modified state list
     final cardId = data.currentCard?.id;
     if (cardId != null) {
       // Create the map {originalIndex: isChecked} from the UPDATED state list for this card
       final Map<int, bool> stateToSave = {
         for (var item in currentCardChecklistStateMutable) item.originalIndex: item.isChecked
       };
       try {
         final persistenceService = await ref.read(persistenceServiceProvider.future);
         await persistenceService.saveChecklistState(cardId, stateToSave);
       } catch (e) { print("Error saving checklist state for card $cardId: $e"); }
     }

     // Recalculate rating color based on the UPDATED state list
     final newRatingColor = _calculateRatingColor(currentCardChecklistStateMutable);

     // Update the main state with the modified checklistItemsState list and new color
     state = AsyncData(data.copyWith(
         checklistItemsState: newChecklistItemsStateList, // Use the updated state list
         currentCardRatingColor: newRatingColor
     ));
  }


  // updateRatingColor remains the same
  void updateRatingColor(int? reportingCardId, Color color) { /* ... */ state.whenData((data) { if (data.sessionComplete) return; final currentCard = data.currentCard; final expectedCardId = currentCard?.id; if (reportingCardId != null && expectedCardId != null && reportingCardId == expectedCardId && data.currentCardRatingColor != color) { final Color colorToSet = (color == const Color(0xFFbdbdbd)) ? InteractiveStudyCard.notRatedColor : color; state = AsyncData(data.copyWith(currentCardRatingColor: colorToSet)); } }); }

  // skipCard remains the same
   void skipCard() { /* ... */ state.whenData((data) { if (data.sessionComplete) return; final currentIndex = data.currentPageIndex; final cardId = data.currentCard?.id; print("Skipping card index: $currentIndex (ID: $cardId)"); _advanceSession(data, currentIndex); }); }


  // *** MODIFIED: rateCard ***
  // Now calculates quality based on the CHECKLIST ITEM STATE list
  Future<void> rateCard() async {
      final currentDataAsync = state;
      if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return;
      final data = currentDataAsync.value!;
      final currentCard = data.currentCard;
      final currentIndex = data.currentPageIndex;

      if (currentCard?.id == null) { /* ... handle missing ID ... */ print("Error: Cannot rate card without an ID. Skipping."); _advanceSession(data, currentIndex); return; }
      final cardId = currentCard!.id!;

      // --- Calculate Quality based on checklistItemsState ---
      int quality;
      // Get the STATE list for the current card
      final currentCardChecklistStateItems = data.currentChecklistItems;
      if (currentCardChecklistStateItems.isEmpty) {
          quality = 3; // Default if no checklist items exist in state
          print("Rating card ID $cardId (no checklist items in state): Default Quality=$quality");
      } else {
          final totalItems = currentCardChecklistStateItems.length;
          final checkedItems = currentCardChecklistStateItems.where((item) => item.isChecked).length;
          final percentage = totalItems > 0 ? (checkedItems / totalItems) : 0.0;
          // Quality calculation logic remains same, just uses state list
          if (percentage == 1.0) { quality = 5; } else if (percentage >= 0.8) { quality = 4; } else if (percentage >= 0.5) { quality = 3; } else if (percentage >= 0.2) { quality = 2; } else if (percentage > 0) { quality = 1; } else { quality = 0; }
          print("Rating card ID $cardId (checklist state ${checkedItems}/${totalItems} = ${percentage.toStringAsFixed(2)}): Calculated Quality=$quality");
      }
      // --- End Quality Calculation ---

      // SR Calculation remains the same
      final SRResult srResult = SRCalculator.calculate( quality: quality, previousEasinessFactor: currentCard.easinessFactor, previousInterval: currentCard.interval, previousRepetitions: currentCard.repetitions );
      DateTime now = DateTime.now(); int calculatedIntervalDays = max(0, srResult.interval); DateTime nextReviewDate = now.add(Duration(days: calculatedIntervalDays)).add(const Duration(seconds: 1));

      // Persist and Update State (logic remains same, uses logging added previously)
      try {
          final dbHelper = await ref.read(databaseHelperProvider.future);
          await dbHelper.updateFlashcardReviewData( cardId, easinessFactor: srResult.easinessFactor, interval: srResult.interval, repetitions: srResult.repetitions, lastReviewed: now, nextReview: nextReviewDate, lastRatingQuality: quality );
          print("  Successfully persisted SR data & Last Quality ($quality) for card ID $cardId: $srResult, Next Review: ${nextReviewDate.toIso8601String()}");

          final updatedCards = List<Flashcard>.from(data.cards);
          final cardIndexInList = updatedCards.indexWhere((c) => c.id == cardId);
          if (cardIndexInList != -1) {
              Flashcard originalCardFromState = updatedCards[cardIndexInList];
              print("--- Question Check Before copyWith ---"); print("Card ID: $cardId"); print("Original Question from State List: ${originalCardFromState.question}"); // Keep this log
              Flashcard cardJustRated = originalCardFromState.copyWith( easinessFactor: srResult.easinessFactor, interval: srResult.interval, repetitions: srResult.repetitions, lastReviewed: () => now, nextReview: () => nextReviewDate, lastRatingQuality: () => quality );
              print("--- Question Check After copyWith ---"); print("Card ID: $cardId"); print("Question in new 'cardJustRated' object: ${cardJustRated.question}"); // Keep this log
              updatedCards[cardIndexInList] = cardJustRated;
              // Pass the state containing the updated cards list to _advanceSession
              _advanceSession(data.copyWith(cards: updatedCards), currentIndex);
          } else { /* ... handle card not found ... */ print("Warning: Rated card $cardId not found..."); _advanceSession(data, currentIndex); }
      } catch (e) { /* ... handle error ... */ print("Error persisting SR data for card ID $cardId: $e"); _advanceSession(data, currentIndex); }
   }


   // deleteCard remains the same
   Future<void> deleteCard(Flashcard cardToDelete) async { /* ... */ if (cardToDelete.id == null) return; final currentDataAsync = state; if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return; final data = currentDataAsync.value!; final cardIndexInList = data.cards.indexWhere((c) => c.id == cardToDelete.id); try { final dbHelper = await ref.read(databaseHelperProvider.future); await dbHelper.deleteFlashcard(cardToDelete.id!); print("Deleted card ID ${cardToDelete.id} from database."); if (cardIndexInList != -1) { _advanceSession(data, cardIndexInList); } else { print("Deleted card was not in list, refreshing study state."); ref.invalidateSelf(); await future; } } catch (e) { print("Error deleting card ID ${cardToDelete.id}: $e"); throw Exception("Error deleting flashcard: $e"); } }
}

// Provider Definition remains the same
final studyProvider = AsyncNotifierProvider.family<StudyNotifier, StudyStateData, int?>(
  () => StudyNotifier(),
);