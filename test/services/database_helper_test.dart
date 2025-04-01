// test/services/database_helper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:path/path.dart' as p;

import 'package:flashcard/services/database_helper.dart';
import 'package:flashcard/services/persistence_service.dart';
import 'package:flashcard/models/folder.dart';
import 'package:flashcard/models/flashcard.dart';

import 'database_helper_test.mocks.dart';

@GenerateMocks([PersistenceService])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --- Global Setup for FFI ---
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate; // Set factory once
  });

  // --- Global Teardown ---
  tearDownAll(() async {
    // Optional: Clean up the final test database file after all tests run
     var dbPath = await getDatabasesPath();
     var fullTestPath = p.join(dbPath, DatabaseHelper_testDbName);
     try {
       // We might need a db instance to close first if one was left open,
       // but the primary goal is deleting the file.
       // Closing might fail if the last test already closed it via tearDown.
       await databaseFactory.deleteDatabase(fullTestPath);
       print("Final test database deleted.");
     } catch (e) {
       print("Error during final DB cleanup: $e");
     }
  });

  // --- Test Suite ---
  // Declare variables needed across groups if setup is complex,
  // but prefer setup within group if possible.
  late MockPersistenceService mockPersistenceService;
  late DatabaseHelper dbHelper;

  // Helper function for group setup to avoid repetition
  Future<void> setupGroupTest() async {
     mockPersistenceService = MockPersistenceService();
     // Define default mock behavior ONCE per setup
     when(mockPersistenceService.clearChecklistState(any)).thenAnswer((_) async {});

     // Ensure DB file from previous group/test is deleted
     var dbPath = await getDatabasesPath();
     var fullTestPath = p.join(dbPath, DatabaseHelper_testDbName);
     await databaseFactory.deleteDatabase(fullTestPath);

     // Create helper with mock for this test group
     dbHelper = DatabaseHelper(mockPersistenceService, dbName: DatabaseHelper_testDbName);
     // Initialize DB for this test
     await dbHelper.database;
  }

  // Helper function for group teardown
  Future<void> teardownGroupTest() async {
     await dbHelper.closeDatabase();
  }


  // === Folder Tests Group ===
  group('Folder Operations', () {
    // Setup before each test *within this group*
    setUp(() async => await setupGroupTest());
    // Teardown after each test *within this group*
    tearDown(() async => await teardownGroupTest());

    test('Insert and Get Root Folders', () async {
      final folder1 = Folder(name: 'Root Folder 1', parentId: null);
      await dbHelper.insertFolder(folder1);
      final folder2 = Folder(name: 'Another Root', parentId: null);
      await dbHelper.insertFolder(folder2);
      final rootFolders = await dbHelper.getFolders(parentId: null);
      expect(rootFolders.length, 2);
      expect(rootFolders, contains(isA<Folder>().having((f) => f.name, 'name', 'Another Root')));
      expect(rootFolders, contains(isA<Folder>().having((f) => f.name, 'name', 'Root Folder 1')));
    });

    test('Insert and Get Subfolders', () async {
      final parentFolder = Folder(name: 'Parent', parentId: null);
      final parentId = await dbHelper.insertFolder(parentFolder);
      final subFolder = Folder(name: 'Subfolder A', parentId: parentId);
      await dbHelper.insertFolder(subFolder);
      final subfolders = await dbHelper.getFolders(parentId: parentId);
      expect(subfolders.length, 1);
      expect(subfolders[0].name, 'Subfolder A');
    });

     test('Get Folder By ID', () async {
        final folder = Folder(name: 'Find Me', parentId: null);
        final id = await dbHelper.insertFolder(folder);
        final foundFolder = await dbHelper.getFolderById(id);
        expect(foundFolder, isNotNull);
        expect(foundFolder!.id, id);
        expect(foundFolder.name, 'Find Me');
    });

    test('Get Folder Path', () async {
        final root = Folder(name: 'Root', parentId: null);
        final rootId = await dbHelper.insertFolder(root);
        final child = Folder(name: 'Child', parentId: rootId);
        final childId = await dbHelper.insertFolder(child);
        final grandchild = Folder(name: 'Grandchild', parentId: childId);
        final grandchildId = await dbHelper.insertFolder(grandchild);
        final path = await dbHelper.getFolderPath(grandchildId);
        expect(path.length, 3);
        expect(path[0].id, rootId);
        expect(path[1].id, childId);
        expect(path[2].id, grandchildId);
    });

    test('Delete Folder Cascades', () async {
      final parent = Folder(name: 'Parent', parentId: null);
      final parentId = await dbHelper.insertFolder(parent);
      final sub = Folder(name: 'Sub', parentId: parentId);
      final subId = await dbHelper.insertFolder(sub);
      final card = Flashcard(question: 'Q', answer: 'A', folderId: subId);
      await dbHelper.insertFlashcard(card);
      await dbHelper.deleteFolder(parentId);
      final parentCheck = await dbHelper.getFolderById(parentId);
      final subCheck = await dbHelper.getFolderById(subId);
      final cardsInSub = await dbHelper.getFlashcards(folderId: subId);
      expect(parentCheck, isNull);
      expect(subCheck, isNull);
      expect(cardsInSub, isEmpty);
    });
  }); // End Folder Operations Group


  // === Flashcard Tests Group ===
  group('Flashcard Operations', () {
    // Setup before each test *within this group*
    setUp(() async => await setupGroupTest());
    // Teardown after each test *within this group*
    tearDown(() async => await teardownGroupTest());

    test('Insert and Get Flashcards (Uncategorized)', () async {
      final card1 = Flashcard(question: 'Q1', answer: 'A1', folderId: null);
      final id1 = await dbHelper.insertFlashcard(card1);
      final uncategorizedCards = await dbHelper.getFlashcards(folderId: null);
      expect(uncategorizedCards.length, 1);
      expect(uncategorizedCards[0].id, id1);
      expect(uncategorizedCards[0].question, 'Q1');
    });

    test('Insert and Get Flashcards (In Folder)', () async {
       final folder = Folder(name: 'My Folder', parentId: null);
       final folderId = await dbHelper.insertFolder(folder);
       final card = Flashcard(question: 'Q Folder', answer: 'A Folder', folderId: folderId);
       final cardId = await dbHelper.insertFlashcard(card);
       final cardsInFolder = await dbHelper.getFlashcards(folderId: folderId);
       expect(cardsInFolder.length, 1);
       expect(cardsInFolder[0].id, cardId);
       expect(cardsInFolder[0].folderId, folderId);
    });

     test('Update Flashcard', () async {
        final card = Flashcard(question: 'Original Q', answer: 'Original A', folderId: null);
        final id = await dbHelper.insertFlashcard(card);
        final updatedCard = card.copyWith(id: id, question: 'Updated Q', answer: 'Updated A');
        final rowsAffected = await dbHelper.updateFlashcard(updatedCard);
        expect(rowsAffected, 1);
        final fetchedCards = await dbHelper.getFlashcards(folderId: null);
        final fetchedCard = fetchedCards.firstWhere((c) => c.id == id);
        expect(fetchedCard.question, 'Updated Q');
        expect(fetchedCard.answer, 'Updated A');
     });

     test('Delete Flashcard successfully calls persistence service', () async {
        final card = Flashcard(question: 'To Delete', answer: 'A', folderId: null);
        final id = await dbHelper.insertFlashcard(card);
        expect((await dbHelper.getFlashcards(folderId: null)).where((c) => c.id == id), isNotEmpty);
        // when(mockPersistenceService.clearChecklistState(id)).thenAnswer((_) async {}); // Default in setUp
        final rowsAffected = await dbHelper.deleteFlashcard(id);
        expect(rowsAffected, 1);
        expect((await dbHelper.getFlashcards(folderId: null)).where((c) => c.id == id), isEmpty);
        verify(mockPersistenceService.clearChecklistState(id)).called(1);
     });

    test('Move Flashcards', () async {
        final folder1 = Folder(name: 'Folder 1');
        final folderId1 = await dbHelper.insertFolder(folder1);
        final folder2 = Folder(name: 'Folder 2');
        final folderId2 = await dbHelper.insertFolder(folder2);
        final card1 = Flashcard(question: 'Card 1', answer: 'A', folderId: folderId1);
        final cardId1 = await dbHelper.insertFlashcard(card1);
        final card2 = Flashcard(question: 'Card 2', answer: 'A', folderId: folderId1);
        final cardId2 = await dbHelper.insertFlashcard(card2);
        await dbHelper.moveFlashcards([cardId1, cardId2], folderId2);
        final cardsInFolder1 = await dbHelper.getFlashcards(folderId: folderId1);
        final cardsInFolder2 = await dbHelper.getFlashcards(folderId: folderId2);
        expect(cardsInFolder1, isEmpty);
        expect(cardsInFolder2.length, 2);
        expect(cardsInFolder2.any((c) => c.id == cardId1), isTrue);
        expect(cardsInFolder2.any((c) => c.id == cardId2), isTrue);
    });

     test('Copy Flashcards', () async {
        final folder1 = Folder(name: 'Folder 1');
        final folderId1 = await dbHelper.insertFolder(folder1);
        final folder2 = Folder(name: 'Folder 2');
        final folderId2 = await dbHelper.insertFolder(folder2);
        final card1 = Flashcard(question: 'Card 1', answer: 'A', folderId: folderId1);
        final cardId1 = await dbHelper.insertFlashcard(card1);
        await dbHelper.copyFlashcards([cardId1], folderId2);
        final cardsInFolder1 = await dbHelper.getFlashcards(folderId: folderId1);
        final cardsInFolder2 = await dbHelper.getFlashcards(folderId: folderId2);
        expect(cardsInFolder1.length, 1);
        expect(cardsInFolder1[0].id, cardId1);
        expect(cardsInFolder2.length, 1);
        expect(cardsInFolder2[0].id, isNot(cardId1));
        expect(cardsInFolder2[0].question, 'Card 1');
        expect(cardsInFolder2[0].folderId, folderId2);
    });
  }); // End Flashcard Operations Group

}

// Helper constant remains the same
const DatabaseHelper_testDbName = 'test_flashcards.db';