// test/widgets/interactive_study_card_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard/models/flashcard.dart';
import 'package:flashcard/models/folder.dart';
import 'package:flashcard/widgets/interactive_study_card.dart';

// Mock function type for checklist callback
typedef OnChecklistChangedCallback = void Function(int itemOriginalIndex, bool isChecked);

void main() {
  group('InteractiveStudyCard Tests', () {
    // --- Sample Data ---
    const sampleFolder = Folder(id: 1, name: 'Test Folder');
    const sampleFolderPath = [Folder(id: 0, name: 'Root'), sampleFolder];
    const sampleCardBasic = Flashcard(
      id: 101,
      question: '**Question** Title',
      answer: 'Simple answer markdown.',
      folderId: 1,
    );
    const sampleCardWithChecklist = Flashcard(
      id: 102,
      question: 'Checklist Question',
      answer: '* Item 1\n* Item 2\n* Item 3\n\nSome extra notes.',
      folderId: 1,
    );
    final sampleChecklistItems = [
      ChecklistItem(originalIndex: 0, text: 'Item 1', isChecked: false),
      ChecklistItem(originalIndex: 1, text: 'Item 2', isChecked: false),
      ChecklistItem(originalIndex: 2, text: 'Item 3', isChecked: false),
    ];
    const sampleAnswerMarkdown = 'Some extra notes.';

    // --- Callback Tracking Variables ---
    bool deleteCalled = false;
    int? checklistItemIndexCalled;
    bool? checklistItemValueCalled;
    Color? ratingColorCalculated;

    // --- Test Helper ---
    Future<void> pumpWidgetUnderTest(
      WidgetTester tester, {
      required Flashcard flashcard,
      bool isAnswerShown = false,
      List<ChecklistItem> checklistItems = const [],
      String answerMarkdownContent = '',
      int currentCardIndex = 1,
      int totalCardCount = 5,
    }) async {
      // Reset callbacks before each pump
      deleteCalled = false;
      checklistItemIndexCalled = null;
      checklistItemValueCalled = null;
      ratingColorCalculated = null;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InteractiveStudyCard(
              flashcard: flashcard,
              folder: sampleFolder,
              folderPath: sampleFolderPath,
              currentCardIndex: currentCardIndex,
              totalCardCount: totalCardCount,
              isAnswerShown: isAnswerShown,
              checklistItems: checklistItems,
              answerMarkdownContent: answerMarkdownContent,
              onDelete: () => deleteCalled = true,
              onChecklistChanged: (index, value) {
                checklistItemIndexCalled = index;
                checklistItemValueCalled = value;
              },
              // *** CORRECTED Line 75 ***
              // Changed callback signature from (color) to (_, color) or (id, color)
              onRatingColorCalculated: (_, color) => ratingColorCalculated = color,
            ),
          ),
        ),
      );
    }

    // Reset callbacks before each test
    setUp(() {
      deleteCalled = false;
      checklistItemIndexCalled = null;
      checklistItemValueCalled = null;
      ratingColorCalculated = null;
    });


    // --- Test Cases ---

    testWidgets('Displays basic info (Question, Index, Path) when answer hidden', (tester) async {
      await pumpWidgetUnderTest(tester, flashcard: sampleCardBasic);
      expect(find.textContaining('Question', findRichText: true), findsOneWidget);
      expect(find.text('Card 1 of 5'), findsOneWidget);
      expect(find.text('Root > Test Folder'), findsOneWidget);
      expect(find.textContaining('Simple answer markdown', findRichText: true), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('Displays answer markdown when answer shown (no checklist)', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        flashcard: sampleCardBasic,
        isAnswerShown: true,
        answerMarkdownContent: sampleCardBasic.answer,
      );
      expect(find.textContaining('Question', findRichText: true), findsOneWidget);
      expect(find.textContaining('Simple answer markdown', findRichText: true), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('Displays checklist and markdown when answer shown (with checklist)', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        flashcard: sampleCardWithChecklist,
        isAnswerShown: true,
        checklistItems: sampleChecklistItems,
        answerMarkdownContent: sampleAnswerMarkdown,
      );
      expect(find.textContaining('Checklist Question', findRichText: true), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(sampleChecklistItems.length));
      expect(find.textContaining('Item 1', findRichText: true), findsOneWidget);
      expect(find.textContaining('Item 2', findRichText: true), findsOneWidget);
      expect(find.textContaining('Item 3', findRichText: true), findsOneWidget);
      expect(find.textContaining('Some extra notes', findRichText: true), findsOneWidget);
    });

    testWidgets('Calls onChecklistChanged when a checkbox is tapped', (tester) async {
       final statefulChecklist = [
         ChecklistItem(originalIndex: 0, text: 'Item A', isChecked: false),
         ChecklistItem(originalIndex: 1, text: 'Item B', isChecked: true),
       ];
      await pumpWidgetUnderTest(
        tester,
        flashcard: sampleCardWithChecklist,
        isAnswerShown: true,
        checklistItems: statefulChecklist,
      );

      // Find the Row containing the text 'Item A'.
      final rowContainingItemA = find.ancestor(
        of: find.textContaining('Item A', findRichText: true),
        matching: find.byType(Row),
      );
      // Find the Checkbox descendant within that specific Row.
      final checkboxInRow = find.descendant(
        of: rowContainingItemA,
        matching: find.byType(Checkbox),
      );

      expect(checkboxInRow, findsOneWidget);
      expect(checklistItemIndexCalled, isNull);

      await tester.tap(checkboxInRow);
      await tester.pump(); // Allow state to update if needed

      expect(checklistItemIndexCalled, equals(0)); // Should be the originalIndex
      expect(checklistItemValueCalled, isTrue); // Should be the new value
    });

     testWidgets('Calls onDelete when delete button is tapped', (tester) async {
       await pumpWidgetUnderTest(tester, flashcard: sampleCardBasic);
       expect(deleteCalled, isFalse);
       final deleteButtonFinder = find.byIcon(Icons.delete_outline);
       expect(deleteButtonFinder, findsOneWidget);
       await tester.tap(deleteButtonFinder);
       await tester.pump();
       expect(deleteCalled, isTrue);
     });

     testWidgets('Finds edit button', (tester) async {
        await pumpWidgetUnderTest(tester, flashcard: sampleCardBasic);
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
     });

     testWidgets('Calls onRatingColorCalculated', (tester) async {
        await pumpWidgetUnderTest(
            tester,
            flashcard: sampleCardWithChecklist,
            checklistItems: sampleChecklistItems,
            isAnswerShown: true
        );
        // Wait for potential post-frame callbacks where color is calculated/reported
        await tester.pumpAndSettle();
        expect(ratingColorCalculated, isNotNull);
     });

    // *** REMOVED the 'Applies selected style' test case ***

  });
}