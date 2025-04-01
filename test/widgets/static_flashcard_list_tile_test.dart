// test/widgets/static_flashcard_list_tile_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard/models/flashcard.dart'; // Import your Flashcard model
import 'package:flashcard/widgets/static_flashcard_list_tile.dart'; // Import the widget to test

void main() {
  // Group tests related to StaticFlashcardListTile
  group('StaticFlashcardListTile Tests', () {

    // Create sample data that will be used in tests
    const testFlashcard = Flashcard(
      id: 1,
      question: 'What is Flutter?',
      answer: 'An open-source UI software development kit.',
      folderId: 10,
    );

    // Define dummy callback functions to track if they were called
    bool editCalled = false;
    bool deleteCalled = false;
    VoidCallback onEdit = () => editCalled = true;
    VoidCallback onDelete = () => deleteCalled = true;

    // Helper function to build the widget within necessary parent widgets (MaterialApp)
    // This provides theme, directionality, etc. needed by ListTile and Card.
    Future<void> pumpWidgetUnderTest(WidgetTester tester, {bool isSelected = false}) async {
      await tester.pumpWidget(
        MaterialApp( // MaterialApp is needed for theme, text styles, etc.
          home: Scaffold( // Scaffold provides a basic layout structure
            body: StaticFlashcardListTile(
              flashcard: testFlashcard,
              onEdit: onEdit,
              onDelete: onDelete,
              isSelected: isSelected,
            ),
          ),
        ),
      );
    }

    // Reset callbacks before each test
    setUp(() {
      editCalled = false;
      deleteCalled = false;
    });

    testWidgets('Displays flashcard question', (WidgetTester tester) async {
      // Build the widget
      await pumpWidgetUnderTest(tester);

      // Verify that the question text is displayed
      // It might be rendered within a Markdown widget, so finding exact text can be tricky.
      // Let's find by type first and then check content if possible, or find a key part.
      expect(find.textContaining('What is Flutter?', findRichText: true), findsOneWidget);
      // Check for the absence of the answer
      expect(find.textContaining('An open-source UI', findRichText: true), findsNothing);
    });

    testWidgets('Shows options menu on long press or options icon tap', (WidgetTester tester) async {
      await pumpWidgetUnderTest(tester);

      // Find the options menu button (IconButton with Icons.more_vert)
      final optionsButtonFinder = find.byIcon(Icons.more_vert);
      expect(optionsButtonFinder, findsOneWidget);

      // Tap the options button
      await tester.tap(optionsButtonFinder);
      // Wait for the menu animation to complete
      await tester.pumpAndSettle();

      // Verify that the 'Edit' and 'Delete' menu items are now visible
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

     testWidgets('Calls onEdit when Edit option is tapped', (WidgetTester tester) async {
      await pumpWidgetUnderTest(tester);

      // Tap the options button to open the menu
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle(); // Wait for menu

      // Verify Edit is initially not called
      expect(editCalled, isFalse);

      // Find and tap the 'Edit' menu item
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle(); // Wait for potential animations/dismissal

      // Verify that the onEdit callback was triggered
      expect(editCalled, isTrue);
      // Verify delete was not called
      expect(deleteCalled, isFalse);
    });

    testWidgets('Calls onDelete when Delete option is tapped', (WidgetTester tester) async {
      await pumpWidgetUnderTest(tester);

      // Tap the options button
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Verify Delete is initially not called
      expect(deleteCalled, isFalse);

      // Find and tap the 'Delete' menu item
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Verify that the onDelete callback was triggered
      expect(deleteCalled, isTrue);
       // Verify edit was not called
      expect(editCalled, isFalse);
    });

     testWidgets('Applies selected style when isSelected is true', (WidgetTester tester) async {
      // Pump widget with isSelected: true
      await pumpWidgetUnderTest(tester, isSelected: true);

      // Find the Card widget
      final cardFinder = find.byType(Card);
      expect(cardFinder, findsOneWidget);

      // Get the Card widget instance
      final Card cardWidget = tester.widget<Card>(cardFinder);

      // Check if the Card's color is applied (it might be slightly different due to opacity)
      // This requires knowing how selection color is applied in your theme or widget.
      // Let's assume it uses theme's primaryContainer with opacity.
      // We can't easily check the exact opacity color, but we can check it's NOT null (default).
      expect(cardWidget.color, isNotNull, reason: "Card color should be non-null when selected");

      // --- Alternative/More Robust Check (If you know the exact theme setup): ---
      // final ThemeData theme = Theme.of(tester.element(cardFinder));
      // final expectedColor = theme.colorScheme.primaryContainer.withOpacity(0.3);
      // expect(cardWidget.color, equals(expectedColor));
      // Note: Exact color matching can be brittle due to minor theme variations. Checking for non-null is often sufficient.

      // Pump widget with isSelected: false
      await pumpWidgetUnderTest(tester, isSelected: false);
      final Card cardWidgetUnselected = tester.widget<Card>(cardFinder);
      // Check if the Card's color is null (default) when not selected
      expect(cardWidgetUnselected.color, isNull, reason: "Card color should be null (default) when not selected");

    });

  });
}