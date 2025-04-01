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
import '../widgets/interactive_study_card.dart'; // Import for color constants
import '../services/database_helper.dart';
import '../services/sr_calculator.dart';

// State class definition
@immutable
class StudyStateData {
  final List<Flashcard> cards;
  final List<Folder> folderPath;
  final List<List<ChecklistItem>> checklistItemsState;
  final List<String> answerMarkdownState;
  final List<bool> answerShownState;
  final int currentPageIndex;
  final Color currentCardRatingColor;
  final bool sessionComplete;
  final int? currentCardLastRatingQuality;

   StudyStateData({
    this.cards = const [],
    this.folderPath = const [],
    this.checklistItemsState = const [],
    this.answerMarkdownState = const [],
    this.answerShownState = const [],
    this.currentPageIndex = 0,
    Color? currentCardRatingColor, // Can be null initially
    this.sessionComplete = false,
    this.currentCardLastRatingQuality,
    // *** FIXED: Initialize with the NEW notRatedColor ***
  }) : currentCardRatingColor = currentCardRatingColor ?? InteractiveStudyCard.notRatedColor;

  bool get isCurrentAnswerShown {
     if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < answerShownState.length) {
       return answerShownState[currentPageIndex];
     }
     return false;
  }

  Flashcard? get currentCard {
      if (!sessionComplete && cards.isNotEmpty && currentPageIndex >= 0 && currentPageIndex < cards.length) {
        return cards[currentPageIndex];
      }
      return null;
    }

  StudyStateData copyWith({
    List<Flashcard>? cards,
    List<Folder>? folderPath,
    List<List<ChecklistItem>>? checklistItemsState,
    List<String>? answerMarkdownState,
    List<bool>? answerShownState,
    int? currentPageIndex,
    Color? currentCardRatingColor,
    bool? sessionComplete,
    ValueGetter<int?>? currentCardLastRatingQuality,
  }) {
    return StudyStateData(
      cards: cards ?? this.cards,
      folderPath: folderPath ?? this.folderPath,
      checklistItemsState: checklistItemsState ?? this.checklistItemsState,
      answerMarkdownState: answerMarkdownState ?? this.answerMarkdownState,
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

// --- StudyNotifier ---
class StudyNotifier extends FamilyAsyncNotifier<StudyStateData, int?> {

  final _random = Random();

  @override
  Future<StudyStateData> build(int? arg /* folderId */) async {
    final folderId = arg;
    if (folderId == null) {
      print("Warning: StudyNotifier build called with null folderId.");
      return StudyStateData(sessionComplete: true);
    }

    final dbHelper = await ref.read(databaseHelperProvider.future);
    final persistenceService = await ref.read(persistenceServiceProvider.future);

    List<Flashcard> studySessionCards;
    final now = DateTime.now();

    // --- Logging for fetching cards ---
    print("StudyNotifier Build: Fetching cards for folder $folderId...");
    List<Flashcard> rawFetchedCards = await dbHelper.getDueFlashcards(folderId: folderId, now: now);
    if (rawFetchedCards.isNotEmpty) {
       print("StudyNotifier Build: Raw fetched DUE cards (first few):");
       for(int i = 0; i < rawFetchedCards.length && i < 5; i++) {
           print("  - ID: ${rawFetchedCards[i].id}, LastQuality: ${rawFetchedCards[i].lastRatingQuality}, Question: ${rawFetchedCards[i].question.substring(0, min(rawFetchedCards[i].question.length, 30))}...");
       }
    } else {
        print("StudyNotifier Build: No due cards found. Fetching all cards...");
        rawFetchedCards = await dbHelper.getFlashcards(folderId: folderId);
        if (rawFetchedCards.isNotEmpty) {
           rawFetchedCards.sort((a, b) { /* Sorting logic */
                final aIsNull = a.nextReview == null;
                final bIsNull = b.nextReview == null;
                if (aIsNull && !bIsNull) return -1;
                if (!aIsNull && bIsNull) return 1;
                if (aIsNull && bIsNull) return 0;
                if (a.nextReview == null || b.nextReview == null) return 0;
                return a.nextReview!.compareTo(b.nextReview!);
            });
           print("StudyNotifier Build: Raw fetched ALL cards (first few, sorted):");
           for(int i = 0; i < rawFetchedCards.length && i < 5; i++) {
               print("  - ID: ${rawFetchedCards[i].id}, LastQuality: ${rawFetchedCards[i].lastRatingQuality}, Question: ${rawFetchedCards[i].question.substring(0, min(rawFetchedCards[i].question.length, 30))}...");
           }
        } else {
            print("StudyNotifier Build: No cards found in folder $folderId at all.");
        }
    }
    studySessionCards = rawFetchedCards;
    // --- End Logging ---


    if (studySessionCards.isEmpty) {
      print("No cards found for study session in folder $folderId.");
      final folderPath = await dbHelper.getFolderPath(folderId);
      return StudyStateData(folderPath: folderPath, sessionComplete: true);
    }

    final List<List<ChecklistItem>> parsedChecklists = [];
    final List<String> parsedAnswerMarkdown = [];
    final List<Map<int, bool>> loadedInitialStates = [];

    for (final card in studySessionCards) {
      final parsedContent = _parseAnswerContent(card.answer);
      parsedChecklists.add(parsedContent.checklistItems);
      parsedAnswerMarkdown.add(parsedContent.markdownContent);
      if (card.id != null) {
        final initialState = await persistenceService.loadChecklistState(card.id);
        loadedInitialStates.add(initialState);
      } else { loadedInitialStates.add({}); }
    }

    final initialChecklistState = _applyInitialStates(parsedChecklists, loadedInitialStates);
    final initialAnswerVisibility = List<bool>.filled(studySessionCards.length, false, growable: true);
    final initialColor = _calculateRatingColor(initialChecklistState.isNotEmpty ? initialChecklistState[0] : []);
    final folderPath = await dbHelper.getFolderPath(folderId);
    final initialLastRatingQuality = studySessionCards[0].lastRatingQuality;
    print("StudyNotifier Build: Setting initial state. First card ID: ${studySessionCards[0].id}, Initial LastQuality: $initialLastRatingQuality");

    return StudyStateData(
      cards: studySessionCards,
      folderPath: folderPath,
      checklistItemsState: initialChecklistState,
      answerMarkdownState: parsedAnswerMarkdown,
      answerShownState: initialAnswerVisibility,
      currentPageIndex: 0,
      currentCardRatingColor: initialColor,
      sessionComplete: false,
      currentCardLastRatingQuality: initialLastRatingQuality,
    );
  }

  // --- Helper Methods (private) ---

  ({ List<ChecklistItem> checklistItems, String markdownContent }) _parseAnswerContent(String answer) {
    final lines = answer.split('\n');
    final List<ChecklistItem> items = [];
    final List<String> markdownLines = [];
    int checklistIndex = 0;
    for (final line in lines) {
      if (line.trim().startsWith('* ')) {
        items.add(ChecklistItem(
          originalIndex: checklistIndex++,
          text: line.substring(line.indexOf('* ') + 2).trim(),
          isChecked: false,
        ));
      } else { markdownLines.add(line); }
    }
    return (checklistItems: items, markdownContent: markdownLines.join('\n').trim());
   }

  List<List<ChecklistItem>> _applyInitialStates(List<List<ChecklistItem>> parsedChecklists, List<Map<int, bool>> initialStates) {
     List<List<ChecklistItem>> statefulChecklists = [];
     for(int i = 0; i < parsedChecklists.length; i++) {
         final cardItems = parsedChecklists[i];
         final cardInitialState = (i < initialStates.length) ? initialStates[i] : <int, bool>{};
         List<ChecklistItem> itemsWithState = [];
         for(final item in cardItems) {
           itemsWithState.add(item.copyWith(isChecked: cardInitialState[item.originalIndex] ?? item.isChecked));
         }
         statefulChecklists.add(itemsWithState);
     }
     return statefulChecklists;
   }

  Color _calculateRatingColor(List<ChecklistItem> checklistItems) {
     // *** FIXED: Use the new notRatedColor as the default/base case ***
     if (checklistItems.isEmpty || !checklistItems.any((item) => item.isChecked)) {
       return InteractiveStudyCard.notRatedColor;
     }
     // Remainder of gradient calculation is the same
     final totalItems = checklistItems.length;
     final checkedItems = checklistItems.where((item) => item.isChecked).length;
     final percentage = totalItems > 0 ? checkedItems / totalItems : 0.0;
     const List<Color> gradientColors = [ InteractiveStudyCard.zeroScoreColor, Colors.orange, Colors.amber, Color(0xFF66BB6A), Colors.blue ];
     const List<double> gradientStops = [ 0.0, 0.25, 0.5, 0.75, 1.0 ];
     final clampedPercentage = percentage.clamp(0.0, 1.0);
     for (int i = 0; i < gradientStops.length - 1; i++) {
       final stop1 = gradientStops[i];
       final stop2 = gradientStops[i + 1];
       if (clampedPercentage >= stop1 && clampedPercentage <= stop2) {
         final range = stop2 - stop1;
         final t = range == 0.0 ? 0.0 : (clampedPercentage - stop1) / range;
         return Color.lerp(gradientColors[i], gradientColors[i + 1], t) ?? gradientColors.last;
       }
     }
     return gradientColors.last;
   }

  // Helper to advance session
  void _advanceSession(StudyStateData currentState, int reviewedCardIndex) {
     if (currentState.sessionComplete) return;
     final updatedSessionCards = List<Flashcard>.from(currentState.cards);
     final updatedChecklists = List<List<ChecklistItem>>.from(currentState.checklistItemsState);
     final updatedMarkdown = List<String>.from(currentState.answerMarkdownState);
     final updatedAnswerShown = List<bool>.from(currentState.answerShownState);

     if (reviewedCardIndex >= 0 && reviewedCardIndex < updatedSessionCards.length) {
       updatedSessionCards.removeAt(reviewedCardIndex);
       updatedChecklists.removeAt(reviewedCardIndex);
       updatedMarkdown.removeAt(reviewedCardIndex);
       updatedAnswerShown.removeAt(reviewedCardIndex);
       print("_advanceSession: Removed card at index $reviewedCardIndex from session queue.");
     } else { print("Warning: Invalid index $reviewedCardIndex provided to _advanceSession."); }

     if (updatedSessionCards.isEmpty) {
        print("_advanceSession: Study session queue empty. Marking session complete.");
        state = AsyncData(currentState.copyWith(
            cards: [], checklistItemsState: [], answerMarkdownState: [], answerShownState: [],
            currentPageIndex: 0, sessionComplete: true, currentCardLastRatingQuality: () => null ));
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
             checklistItemsState: updatedChecklists,
             answerMarkdownState: updatedMarkdown,
             answerShownState: updatedAnswerShown
         ),
         nextIndex
     );
  }

  // Helper to update state for the new current card index
  void _updateStateForNewIndex(StudyStateData currentState, int newIndex) {
     if (currentState.sessionComplete) return;
     if (newIndex < 0 || newIndex >= currentState.cards.length) {
        print("Warning: Attempted state update for invalid newIndex $newIndex. Current card count: ${currentState.cards.length}. Setting session complete.");
         state = AsyncData(currentState.copyWith(sessionComplete: true, currentCardLastRatingQuality: () => null));
         return;
     }

     final newAnswerState = List<bool>.from(currentState.answerShownState);
     if (newIndex < newAnswerState.length) {
        newAnswerState[newIndex] = false;
     } else {
        print("Warning: Answer state list length mismatch in _updateStateForNewIndex.");
     }

     final newChecklist = (newIndex >= 0 && newIndex < currentState.checklistItemsState.length)
         ? currentState.checklistItemsState[newIndex] : <ChecklistItem>[];
     final newRatingColor = _calculateRatingColor(newChecklist);
     final newLastRatingQuality = currentState.cards[newIndex].lastRatingQuality;
     print("_updateStateForNewIndex: Updating state for index $newIndex. Card ID: ${currentState.cards[newIndex].id}, LastQuality from state list: $newLastRatingQuality");

     state = AsyncData(currentState.copyWith(
         currentPageIndex: newIndex,
         answerShownState: newAnswerState,
         currentCardRatingColor: newRatingColor,
         currentCardLastRatingQuality: () => newLastRatingQuality,
         sessionComplete: false
     ));
  }

  // --- Public Methods to Modify State ---

  void toggleAnswerVisibility() {
    state.whenData((data) {
       if (!data.sessionComplete && data.cards.isNotEmpty && data.currentPageIndex >= 0 && data.currentPageIndex < data.answerShownState.length) {
          final newAnswerState = List<bool>.from(data.answerShownState);
          newAnswerState[data.currentPageIndex] = !newAnswerState[data.currentPageIndex];
          state = AsyncData(data.copyWith(answerShownState: newAnswerState));
       }
    });
   }

  Future<void> handleChecklistChanged(int itemOriginalIndex, bool isChecked) async {
     final currentDataAsync = state;
     if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return;
     final data = currentDataAsync.value!;
     if (data.currentPageIndex < 0 || data.currentPageIndex >= data.checklistItemsState.length) {
         print("Error: Invalid currentPageIndex ${data.currentPageIndex} in handleChecklistChanged.");
         return;
     }

     final newChecklistItemsState = List<List<ChecklistItem>>.from(
         data.checklistItemsState.map((list) => List<ChecklistItem>.from(list.map((item) => item.copyWith())))
     );
     final currentCardChecklistMutable = newChecklistItemsState[data.currentPageIndex];
     final itemIndex = currentCardChecklistMutable.indexWhere((item) => item.originalIndex == itemOriginalIndex);

     if (itemIndex == -1) {
         print("Error: Checklist item with originalIndex $itemOriginalIndex not found.");
         return;
     }
     currentCardChecklistMutable[itemIndex] = currentCardChecklistMutable[itemIndex].copyWith(isChecked: isChecked);

     final cardId = data.currentCard?.id;
     if (cardId != null) {
       final Map<int, bool> stateToSave = { for (var item in currentCardChecklistMutable) item.originalIndex: item.isChecked };
       try {
         final persistenceService = await ref.read(persistenceServiceProvider.future);
         await persistenceService.saveChecklistState(cardId, stateToSave);
       } catch (e) {
         print("Error saving checklist state for card $cardId: $e");
       }
     }

     final newRatingColor = _calculateRatingColor(currentCardChecklistMutable);
     state = AsyncData(data.copyWith(
         checklistItemsState: newChecklistItemsState,
         currentCardRatingColor: newRatingColor
     ));
  }

  // Updated signature slightly - removed optional parameter as it wasn't used effectively
  void updateRatingColor(int? reportingCardId, Color color) {
      state.whenData((data) {
        if (data.sessionComplete) return;
        final currentCard = data.currentCard;
        final expectedCardId = currentCard?.id;
        // Only update if the reporting card matches the current card AND the color is different
        if (reportingCardId != null && expectedCardId != null && reportingCardId == expectedCardId && data.currentCardRatingColor != color) {
           // Check if the incoming color matches the old grey, if so, use the new grey from the constant
           final Color colorToSet = (color == const Color(0xFFbdbdbd) /* Approximate old Colors.grey[400] */)
                                    ? InteractiveStudyCard.notRatedColor
                                    : color;
           state = AsyncData(data.copyWith(currentCardRatingColor: colorToSet));
        }
      });
   }


   void skipCard() {
      state.whenData((data) {
          if (data.sessionComplete) return;
          final currentIndex = data.currentPageIndex;
          final cardId = data.currentCard?.id;
          print("Skipping card index: $currentIndex (ID: $cardId)");
          _advanceSession(data, currentIndex);
      });
   }

  Future<void> rateCard() async {
      final currentDataAsync = state;
      if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return;
      final data = currentDataAsync.value!;
      final currentCard = data.currentCard;
      final currentIndex = data.currentPageIndex;

      if (currentCard?.id == null) {
          print("Error: Cannot rate card without an ID. Skipping.");
          _advanceSession(data, currentIndex);
          return;
      }
      final cardId = currentCard!.id!;

      int quality; // Quality calculation logic remains the same
      final currentChecklistItems = (currentIndex >= 0 && currentIndex < data.checklistItemsState.length)
                                       ? data.checklistItemsState[currentIndex] : <ChecklistItem>[];
      if (currentChecklistItems.isEmpty) {
          quality = 3;
          print("Rating card ID $cardId (no checklist): Default Quality=$quality");
      } else {
          final totalItems = currentChecklistItems.length;
          final checkedItems = currentChecklistItems.where((item) => item.isChecked).length;
          final percentage = totalItems > 0 ? (checkedItems / totalItems) : 0.0;
          if (percentage == 1.0) { quality = 5; }
          else if (percentage >= 0.8) { quality = 4; }
          else if (percentage >= 0.5) { quality = 3; }
          else if (percentage >= 0.2) { quality = 2; }
          else if (percentage > 0) { quality = 1; }
          else { quality = 0; }
          print("Rating card ID $cardId (checklist ${checkedItems}/${totalItems} = ${percentage.toStringAsFixed(2)}): Calculated Quality=$quality");
      }

      final SRResult srResult = SRCalculator.calculate( /* SR calculation remains the same */
          quality: quality,
          previousEasinessFactor: currentCard.easinessFactor,
          previousInterval: currentCard.interval,
          previousRepetitions: currentCard.repetitions,
      );

      DateTime now = DateTime.now();
      int calculatedIntervalDays = max(0, srResult.interval);
      DateTime nextReviewDate = now.add(Duration(days: calculatedIntervalDays)).add(const Duration(seconds: 1));

      try {
          final dbHelper = await ref.read(databaseHelperProvider.future);
          await dbHelper.updateFlashcardReviewData( /* DB update remains the same */
              cardId,
              easinessFactor: srResult.easinessFactor,
              interval: srResult.interval,
              repetitions: srResult.repetitions,
              lastReviewed: now,
              nextReview: nextReviewDate,
              lastRatingQuality: quality,
          );
          print("  Successfully persisted SR data & Last Quality ($quality) for card ID $cardId: $srResult, Next Review: ${nextReviewDate.toIso8601String()}");

          final updatedCards = List<Flashcard>.from(data.cards);
          final cardIndexInList = updatedCards.indexWhere((c) => c.id == cardId);
          if (cardIndexInList != -1) {
              Flashcard cardJustRated = updatedCards[cardIndexInList].copyWith( /* Update local card copy */
                  easinessFactor: srResult.easinessFactor,
                  interval: srResult.interval,
                  repetitions: srResult.repetitions,
                  lastReviewed: () => now,
                  nextReview: () => nextReviewDate,
                  lastRatingQuality: () => quality,
              );
              updatedCards[cardIndexInList] = cardJustRated;
              _advanceSession(data.copyWith(cards: updatedCards), currentIndex);
          } else {
             print("Warning: Rated card $cardId not found in current session list after DB update.");
             _advanceSession(data, currentIndex);
          }
      } catch (e) {
          print("Error persisting SR data for card ID $cardId: $e");
          _advanceSession(data, currentIndex);
      }
   }

   Future<void> deleteCard(Flashcard cardToDelete) async { // Delete logic remains the same
      if (cardToDelete.id == null) return;
      final currentDataAsync = state;
      if (!currentDataAsync.hasValue || currentDataAsync.value!.sessionComplete) return;
      final data = currentDataAsync.value!;
      final cardIndexInList = data.cards.indexWhere((c) => c.id == cardToDelete.id);

      try {
        final dbHelper = await ref.read(databaseHelperProvider.future);
        await dbHelper.deleteFlashcard(cardToDelete.id!);
        print("Deleted card ID ${cardToDelete.id} from database.");
         if (cardIndexInList != -1) {
             _advanceSession(data, cardIndexInList);
         } else {
             print("Deleted card was not in list, refreshing study state.");
             ref.invalidateSelf();
             await future;
         }
      } catch (e) {
        print("Error deleting card ID ${cardToDelete.id}: $e");
        throw Exception("Error deleting flashcard: $e");
      }
   }
}

// Provider Definition
final studyProvider = AsyncNotifierProvider.family<StudyNotifier, StudyStateData, int?>(
  () => StudyNotifier(),
);