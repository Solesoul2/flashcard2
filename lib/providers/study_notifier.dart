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
import '../services/persistence_service.dart'; // Needed for checklist state and settings

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
  // Holds the checklist items separately for state management (checked status)
  // Kept sorted (checked items at the bottom) within the notifier.
  final List<List<ChecklistItem>> checklistItemsState;
  final List<bool> answerShownState;
  final int currentPageIndex;
  final Color currentCardRatingColor;
  final bool sessionComplete;
  final int? currentCardLastRatingQuality;
  // --- NEW: Study Settings ---
  final bool setting1HideUnmarkedTextWithCheckboxesActive; // Req 1
  final bool setting2ShowPreviouslyCheckedItemsActive; // Req 2

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
    // Initialize settings (defaults can be adjusted if needed)
    this.setting1HideUnmarkedTextWithCheckboxesActive = true,
    this.setting2ShowPreviouslyCheckedItemsActive = true,
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
    // --- NEW: Settings in copyWith ---
    bool? setting1HideUnmarkedTextWithCheckboxesActive,
    bool? setting2ShowPreviouslyCheckedItemsActive,
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
      // --- NEW: Apply settings updates ---
      setting1HideUnmarkedTextWithCheckboxesActive: setting1HideUnmarkedTextWithCheckboxesActive ?? this.setting1HideUnmarkedTextWithCheckboxesActive,
      setting2ShowPreviouslyCheckedItemsActive: setting2ShowPreviouslyCheckedItemsActive ?? this.setting2ShowPreviouslyCheckedItemsActive,
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
           currentCardLastRatingQuality == other.currentCardLastRatingQuality &&
           // --- NEW: Compare settings ---
           setting1HideUnmarkedTextWithCheckboxesActive == other.setting1HideUnmarkedTextWithCheckboxesActive &&
           setting2ShowPreviouslyCheckedItemsActive == other.setting2ShowPreviouslyCheckedItemsActive;

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
       currentCardLastRatingQuality.hashCode ^
       // --- NEW: Hash settings ---
       setting1HideUnmarkedTextWithCheckboxesActive.hashCode ^
       setting2ShowPreviouslyCheckedItemsActive.hashCode;
}
// --- End MODIFIED State ---

// --- StudyNotifier ---
class StudyNotifier extends FamilyAsyncNotifier<StudyStateData, int?> {

  final _random = Random();

  // Helper function to sort a list of ChecklistItems (checked items last)
  List<ChecklistItem> _sortChecklist(List<ChecklistItem> items) {
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
        print("Warning: StudyNotifier build called with null folderId.");
        // Load settings even if no folder ID, maybe show message later
        final persistenceService = await ref.read(persistenceServiceProvider.future);
        final loadedSettings = await persistenceService.loadStudySettings();
        return StudyStateData(
            sessionComplete: true,
            setting1HideUnmarkedTextWithCheckboxesActive: loadedSettings['setting1Active'] ?? true,
            setting2ShowPreviouslyCheckedItemsActive: loadedSettings['setting2Active'] ?? true,
        );
    }

    // --- Load Services ---
    final dbHelper = await ref.read(databaseHelperProvider.future);
    final persistenceService = await ref.read(persistenceServiceProvider.future);
    // --- Load Settings FIRST ---
    final loadedSettings = await persistenceService.loadStudySettings();
    final bool initialSetting1 = loadedSettings['setting1Active'] ?? true;
    final bool initialSetting2 = loadedSettings['setting2Active'] ?? true;

    // --- Fetch Cards (remains the same) ---
    List<Flashcard> studySessionCards;
    final now = DateTime.now();
    print("StudyNotifier Build: Fetching cards for folder $folderId...");
    List<Flashcard> rawFetchedCards = await dbHelper.getDueFlashcards(folderId: folderId, now: now);
    if (rawFetchedCards.isEmpty) {
        print("StudyNotifier Build: No due cards found. Fetching all cards...");
        rawFetchedCards = await dbHelper.getFlashcards(folderId: folderId);
        if (rawFetchedCards.isNotEmpty) {
            rawFetchedCards.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
        }
    }
    studySessionCards = rawFetchedCards;
    if (studySessionCards.isNotEmpty) { print("StudyNotifier Build: Fetched ${studySessionCards.length} cards..."); }
    else { print("StudyNotifier Build: No cards found for folder $folderId."); }

    // --- Handle No Cards Case (after loading settings) ---
    if (studySessionCards.isEmpty) {
        print("No cards found for study session in folder $folderId.");
        final folderPath = await dbHelper.getFolderPath(folderId);
        return StudyStateData(
            folderPath: folderPath,
            sessionComplete: true,
            setting1HideUnmarkedTextWithCheckboxesActive: initialSetting1, // Include settings
            setting2ShowPreviouslyCheckedItemsActive: initialSetting2,   // Include settings
        );
    }

    // --- Parsing and State Initialization (remains the same) ---
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
    final initialChecklistStateWithPersistence = _applyInitialCheckStates(
      allChecklistItemsForState, loadedInitialCheckStates
    );
    // --- End Parsing ---


    final initialAnswerVisibility = List<bool>.filled(studySessionCards.length, false, growable: true);
    final initialColor = _calculateRatingColor(initialChecklistStateWithPersistence.isNotEmpty ? initialChecklistStateWithPersistence[0] : []);
    final folderPath = await dbHelper.getFolderPath(folderId);
    final initialLastRatingQuality = studySessionCards.isNotEmpty ? studySessionCards[0].lastRatingQuality : null;
    if(studySessionCards.isNotEmpty) { print("StudyNotifier Build: Setting initial state. First card ID: ${studySessionCards[0].id}, Initial LastQuality: $initialLastRatingQuality"); }

    // --- Create initial state including settings ---
    return StudyStateData(
      cards: studySessionCards,
      folderPath: folderPath,
      orderedAnswerLinesState: allOrderedLines,
      checklistItemsState: initialChecklistStateWithPersistence, // Sorted list
      answerShownState: initialAnswerVisibility,
      currentPageIndex: 0,
      currentCardRatingColor: initialColor,
      sessionComplete: false,
      currentCardLastRatingQuality: initialLastRatingQuality,
      // Include loaded settings
      setting1HideUnmarkedTextWithCheckboxesActive: initialSetting1,
      setting2ShowPreviouslyCheckedItemsActive: initialSetting2,
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

  // _applyInitialCheckStates (applies state AND sorts) remains the same
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

  // _advanceSession (removes card and updates index) remains the same
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

     int nextIndex = reviewedCardIndex;
     if (nextIndex >= updatedSessionCards.length) {
         nextIndex = 0;
     }

     print("_advanceSession: Next index will be $nextIndex");
     _updateStateForNewIndex(
         currentState.copyWith(
             cards: updatedSessionCards,
             orderedAnswerLinesState: updatedOrderedLines,
             checklistItemsState: updatedChecklistItems,
             answerShownState: updatedAnswerShown
             // Settings are carried over by copyWith
         ),
         nextIndex
     );
  }

  // _updateStateForNewIndex (sets state for the new card) remains the same
  void _updateStateForNewIndex(StudyStateData currentState, int newIndex) {
     if (currentState.sessionComplete) return;
     if (newIndex < 0 || newIndex >= currentState.cards.length) { print("Warning: Attempted state update for invalid newIndex $newIndex..."); state = AsyncData(currentState.copyWith(sessionComplete: true, currentCardLastRatingQuality: () => null)); return; }

     final newAnswerState = List<bool>.from(currentState.answerShownState);
     if (newIndex < newAnswerState.length) { newAnswerState[newIndex] = false; }
     else { print("Warning: Answer state list length mismatch in _updateStateForNewIndex. Length: ${newAnswerState.length}, Index: $newIndex"); }

     final currentCardChecklistState = (newIndex >= 0 && newIndex < currentState.checklistItemsState.length)
         ? currentState.checklistItemsState[newIndex] : <ChecklistItem>[];
     final newRatingColor = _calculateRatingColor(currentCardChecklistState);
     final newLastRatingQuality = currentState.cards[newIndex].lastRatingQuality;
     print("_updateStateForNewIndex: Updating state for index $newIndex. Card ID: ${currentState.cards[newIndex].id}, LastQuality from state list: $newLastRatingQuality");

     state = AsyncData(currentState.copyWith(
         currentPageIndex: newIndex,
         answerShownState: newAnswerState,
         currentCardRatingColor: newRatingColor,
         currentCardLastRatingQuality: () => newLastRatingQuality,
         sessionComplete: false
         // checklistItemsState is already updated/sorted
         // Settings are carried over by copyWith
     ));
  }

  // toggleAnswerVisibility remains the same
  void toggleAnswerVisibility() { state.whenData((data) { if (!data.sessionComplete && data.cards.isNotEmpty && data.currentPageIndex >= 0 && data.currentPageIndex < data.answerShownState.length) { final newAnswerState = List<bool>.from(data.answerShownState); newAnswerState[data.currentPageIndex] = !newAnswerState[data.currentPageIndex]; state = AsyncData(data.copyWith(answerShownState: newAnswerState)); } }); }

  // handleChecklistChanged (updates checklist, sorts, persists) remains the same
  Future<void> handleChecklistChanged(int itemOriginalIndex, bool isChecked) async {
     final currentDataAsync = state;
     if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return;
     final data = currentDataAsync.value!;
     final currentIndex = data.currentPageIndex;

      if (currentIndex < 0 || currentIndex >= data.checklistItemsState.length) {
          print("Error: Invalid currentPageIndex $currentIndex in handleChecklistChanged.");
          return;
      }

     final newChecklistItemsStateList = List<List<ChecklistItem>>.from(
         data.checklistItemsState.map((list) => List<ChecklistItem>.from(list.map((item) => item.copyWith())))
     );
     final currentCardChecklistStateMutable = newChecklistItemsStateList[currentIndex];
     final itemIndexInState = currentCardChecklistStateMutable.indexWhere((item) => item.originalIndex == itemOriginalIndex);

     if (itemIndexInState == -1) {
         print("Error: Checklist item state with originalIndex $itemOriginalIndex not found for card at index $currentIndex.");
         return;
     }

     currentCardChecklistStateMutable[itemIndexInState] = currentCardChecklistStateMutable[itemIndexInState].copyWith(isChecked: isChecked);

     // Re-sort the checklist for the current card
     final sortedCurrentCardChecklist = _sortChecklist(currentCardChecklistStateMutable);
     newChecklistItemsStateList[currentIndex] = sortedCurrentCardChecklist;

     // Persist state
     final cardId = data.currentCard?.id;
     if (cardId != null) {
       final Map<int, bool> stateToSave = { for (var item in currentCardChecklistStateMutable) item.originalIndex: item.isChecked };
       try {
         final persistenceService = await ref.read(persistenceServiceProvider.future);
         await persistenceService.saveChecklistState(cardId, stateToSave);
       } catch (e) { print("Error saving checklist state for card $cardId: $e"); }
     }

     final newRatingColor = _calculateRatingColor(sortedCurrentCardChecklist); // Use sorted list for color

     state = AsyncData(data.copyWith(
         checklistItemsState: newChecklistItemsStateList, // Store the list containing the sorted sublist
         currentCardRatingColor: newRatingColor
     ));
  }

  // updateRatingColor remains the same
  void updateRatingColor(int? reportingCardId, Color color) { state.whenData((data) { if (data.sessionComplete) return; final currentCard = data.currentCard; final expectedCardId = currentCard?.id; if (reportingCardId != null && expectedCardId != null && reportingCardId == expectedCardId && data.currentCardRatingColor != color) { final Color colorToSet = (color == const Color(0xFFbdbdbd)) ? InteractiveStudyCard.notRatedColor : color; state = AsyncData(data.copyWith(currentCardRatingColor: colorToSet)); } }); }

  // skipCard remains the same
   void skipCard() { state.whenData((data) { if (data.sessionComplete) return; final currentIndex = data.currentPageIndex; final cardId = data.currentCard?.id; print("Skipping card index: $currentIndex (ID: $cardId)"); _advanceSession(data, currentIndex); }); }

  // rateCard (calculates quality, persists SR, advances) remains the same
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

      final SRResult srResult = SRCalculator.calculate( quality: quality, previousEasinessFactor: currentCard.easinessFactor, previousInterval: currentCard.interval, previousRepetitions: currentCard.repetitions );
      DateTime now = DateTime.now(); int calculatedIntervalDays = max(0, srResult.interval); DateTime nextReviewDate = now.add(Duration(days: calculatedIntervalDays)).add(const Duration(seconds: 1));

      try {
          final dbHelper = await ref.read(databaseHelperProvider.future);
          await dbHelper.updateFlashcardReviewData( cardId, easinessFactor: srResult.easinessFactor, interval: srResult.interval, repetitions: srResult.repetitions, lastReviewed: now, nextReview: nextReviewDate, lastRatingQuality: quality );
          print("  Successfully persisted SR data & Last Quality ($quality) for card ID $cardId: $srResult, Next Review: ${nextReviewDate.toIso8601String()}");

          final updatedCards = List<Flashcard>.from(data.cards);
          final cardIndexInList = updatedCards.indexWhere((c) => c.id == cardId);
          if (cardIndexInList != -1) {
              Flashcard originalCardFromState = updatedCards[cardIndexInList];
              Flashcard cardJustRated = originalCardFromState.copyWith(
                  easinessFactor: srResult.easinessFactor, interval: srResult.interval,
                  repetitions: srResult.repetitions, lastReviewed: () => now,
                  nextReview: () => nextReviewDate, lastRatingQuality: () => quality
              );
              updatedCards[cardIndexInList] = cardJustRated;
              _advanceSession(data.copyWith(cards: updatedCards), currentIndex);
          } else {
              print("Warning: Rated card $cardId not found in current session list after DB update. Advancing without state update.");
              _advanceSession(data, currentIndex);
          }
      } catch (e) { print("Error persisting SR data for card ID $cardId: $e"); _advanceSession(data, currentIndex); }
   }


   // deleteCard remains the same
   Future<void> deleteCard(Flashcard cardToDelete) async { if (cardToDelete.id == null) return; final currentDataAsync = state; if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return; final data = currentDataAsync.value!; final cardIndexInList = data.cards.indexWhere((c) => c.id == cardToDelete.id); try { final dbHelper = await ref.read(databaseHelperProvider.future); await dbHelper.deleteFlashcard(cardToDelete.id!); print("Deleted card ID ${cardToDelete.id} from database."); if (cardIndexInList != -1) { _advanceSession(data, cardIndexInList); } else { print("Deleted card was not in list, refreshing study state."); ref.invalidateSelf(); await future; } } catch (e) { print("Error deleting card ID ${cardToDelete.id}: $e"); throw Exception("Error deleting flashcard: $e"); } }

  // refreshSingleCard (updates one card's state after edit) remains the same
  Future<void> refreshSingleCard(int cardId) async {
    final currentDataAsync = state;
    if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) {
        print("StudyNotifier: Cannot refresh single card, state is invalid or session complete.");
        return;
    }
    final data = currentDataAsync.value!;

    print("StudyNotifier: Refreshing single card ID: $cardId");

    try {
      final dbHelper = await ref.read(databaseHelperProvider.future);
      final persistenceService = await ref.read(persistenceServiceProvider.future);

      final List<Map<String, dynamic>> maps = await (await dbHelper.database).query(
         DatabaseHelper.flashcardsTable,
         columns: [ 'id', 'question', 'answer', 'folderId', 'easinessFactor', 'interval', 'repetitions', 'lastReviewed', 'nextReview', 'lastRatingQuality' ],
         where: 'id = ?', whereArgs: [cardId], limit: 1,
      );

      if (maps.isEmpty) {
        print("  > Card ID $cardId not found in DB during refresh. Maybe deleted during edit?");
        ref.invalidateSelf(); await future; return;
      }

      final updatedCard = Flashcard.fromMap(maps.first);
      print("  > Fetched updated card data. Question: '${updatedCard.question.substring(0, min(updatedCard.question.length, 50)).replaceAll('\n', '\\n')}...'");
      final indexInState = data.cards.indexWhere((card) => card.id == cardId);

      if (indexInState == -1) {
        print("  > Card ID $cardId not found in current session state list. Invalidating.");
         ref.invalidateSelf(); await future; return;
      }
      print("  > Card found at index $indexInState in current state list.");

      final updatedCardsList = List<Flashcard>.from(data.cards);
      final updatedOrderedLinesList = List<List<ParsedAnswerLine>>.from(data.orderedAnswerLinesState);
      final updatedChecklistItemsList = List<List<ChecklistItem>>.from(data.checklistItemsState); // Contains sorted sublists

      // Update lists at index
      updatedCardsList[indexInState] = updatedCard;
      final parseResult = _parseAnswerContent(updatedCard.answer);
      updatedOrderedLinesList[indexInState] = parseResult.orderedLines;
      final persistedCheckState = await persistenceService.loadChecklistState(cardId);
      List<ChecklistItem> itemsWithState = [];
       for(final item in parseResult.checklistItems) { itemsWithState.add(item.copyWith( isChecked: persistedCheckState[item.originalIndex] ?? item.isChecked )); }
      updatedChecklistItemsList[indexInState] = _sortChecklist(itemsWithState); // Apply state and sort

      print("  > Updated card, ordered lines, and checklist state at index $indexInState.");

      state = AsyncData(data.copyWith(
        cards: updatedCardsList,
        orderedAnswerLinesState: updatedOrderedLinesList,
        checklistItemsState: updatedChecklistItemsList,
        // Keep other state like currentPageIndex, sessionComplete etc.
        // UI will react to the updated data for the current card.
      ));
       print("StudyNotifier: Single card refresh complete for ID: $cardId. State updated.");

    } catch (e, stackTrace) {
      print("Error refreshing single card ID $cardId: $e\n$stackTrace");
      state = AsyncError(e, stackTrace);
    }
  }

  // --- NEW: Methods to Toggle Settings ---

  /// Toggles the state of Setting 1 (Hide unmarked text followed by checkboxes).
  Future<void> toggleSetting1() async {
    final currentDataAsync = state;
    if (!currentDataAsync.hasValue) return; // Don't toggle if state isn't ready
    final data = currentDataAsync.value!;

    final newSetting1State = !data.setting1HideUnmarkedTextWithCheckboxesActive;

    // Update state immediately for UI responsiveness
    state = AsyncData(data.copyWith(
      setting1HideUnmarkedTextWithCheckboxesActive: newSetting1State,
    ));

    // Persist the new settings state
    try {
      final persistenceService = await ref.read(persistenceServiceProvider.future);
      await persistenceService.saveStudySettings(
        setting1Active: newSetting1State,
        setting2Active: data.setting2ShowPreviouslyCheckedItemsActive, // Keep other setting as is
      );
      print("Toggled and saved Setting 1 to: $newSetting1State");
    } catch (e) {
      print("Error saving Setting 1 state: $e");
      // Optionally revert state or show error
    }
  }

  /// Toggles the state of Setting 2 (Show previously checked items).
  Future<void> toggleSetting2() async {
    final currentDataAsync = state;
    if (!currentDataAsync.hasValue) return; // Don't toggle if state isn't ready
    final data = currentDataAsync.value!;

    final newSetting2State = !data.setting2ShowPreviouslyCheckedItemsActive;

    // Update state immediately for UI responsiveness
    state = AsyncData(data.copyWith(
      setting2ShowPreviouslyCheckedItemsActive: newSetting2State,
    ));

    // Persist the new settings state
    try {
      final persistenceService = await ref.read(persistenceServiceProvider.future);
      await persistenceService.saveStudySettings(
        setting1Active: data.setting1HideUnmarkedTextWithCheckboxesActive, // Keep other setting as is
        setting2Active: newSetting2State,
      );
       print("Toggled and saved Setting 2 to: $newSetting2State");
    } catch (e) {
      print("Error saving Setting 2 state: $e");
      // Optionally revert state or show error
    }
  }
  // --- END NEW Methods ---

}

// Provider Definition remains the same
final studyProvider = AsyncNotifierProvider.family<StudyNotifier, StudyStateData, int?>(
  () => StudyNotifier(),
);