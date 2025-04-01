// lib/services/database_helper.dart
import 'dart:async'; // For Completer
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/flashcard.dart';
import '../models/folder.dart';
import 'persistence_service.dart';

class DatabaseHelper {
  final PersistenceService _persistenceService;
  final String _dbName;

  Completer<Database>? _dbOpenCompleter;

  // --- Constants ---
  static const String _prodDbName = 'flashcards.db';
  static const String _defaultTestDbName = 'test_flashcards.db';
  static const String _foldersTable = 'folders';
  static const String _flashcardsTable = 'flashcards';
  static const String _colId = 'id';
  static const String _colName = 'name';
  static const String _colParentId = 'parentId';
  static const String _colQuestion = 'question';
  static const String _colAnswer = 'answer';
  static const String _colFolderId = 'folderId';

  // Spaced Repetition Columns
  static const String _colEasinessFactor = 'easinessFactor';
  static const String _colInterval = 'interval';
  static const String _colRepetitions = 'repetitions';
  static const String _colLastReviewed = 'lastReviewed';
  static const String _colNextReview = 'nextReview';
  // New Column for last rating quality
  static const String _colLastRatingQuality = 'lastRatingQuality';


  static const int uncategorizedFolderIdSentinel = -999;

  // Current Database Version - Incremented to 4
  static const int _currentDbVersion = 4;

  DatabaseHelper(this._persistenceService, {String? dbName})
      : _dbName = dbName ?? (_isRunningInTest() ? _defaultTestDbName : _prodDbName);

  static bool _isRunningInTest() {
     final factoryType = databaseFactory.runtimeType.toString();
     return factoryType.contains('SqfliteDatabaseFactoryFfi') ||
            factoryType.contains('SqfliteDatabaseFactoryFfiNoIsolate');
  }

  Future<Database> get database {
    if (_dbOpenCompleter == null) {
      _dbOpenCompleter = Completer();
      _initDatabase(_dbName).then((db) {
        _dbOpenCompleter!.complete(db);
      }).catchError((error, stackTrace) {
        print("Database initialization failed: $error\n$stackTrace");
        _dbOpenCompleter!.completeError(error, stackTrace);
        _dbOpenCompleter = null;
      });
    }
    return _dbOpenCompleter!.future;
  }

  Future<Database> _initDatabase(String dbName) async {
    String? databasesPath = await getDatabasesPath();
    if (databasesPath == null) {
      throw Exception("Error: Could not determine database path.");
    }
    final String dbPath = p.join(databasesPath, dbName);
    print("Initializing database at final path: $dbPath (Version: $_currentDbVersion)");

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _currentDbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    print("Creating database schema version $version...");
    await db.execute('''
      CREATE TABLE $_foldersTable (
        $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_colName TEXT NOT NULL,
        $_colParentId INTEGER,
        FOREIGN KEY ($_colParentId) REFERENCES $_foldersTable($_colId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE $_flashcardsTable (
        $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_colQuestion TEXT NOT NULL,
        $_colAnswer TEXT NOT NULL,
        $_colFolderId INTEGER,
        $_colEasinessFactor REAL DEFAULT 2.5,
        $_colInterval INTEGER DEFAULT 0,
        $_colRepetitions INTEGER DEFAULT 0,
        $_colLastReviewed TEXT,
        $_colNextReview TEXT,
        $_colLastRatingQuality INTEGER, -- Added new column
        FOREIGN KEY ($_colFolderId) REFERENCES $_foldersTable($_colId) ON DELETE CASCADE
      )
    ''');
    print("Database schema created.");
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print("Upgrading database from version $oldVersion to $newVersion...");
    if (oldVersion < 2) {
      try {
        print("Applying migration v1 -> v2 (Folders)...");
        // ... (migration v1 -> v2 code remains the same) ...
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_foldersTable (
            $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
            $_colName TEXT NOT NULL,
            $_colParentId INTEGER,
            FOREIGN KEY ($_colParentId) REFERENCES $_foldersTable($_colId) ON DELETE CASCADE
          )
        ''');
        print("Ensured '$_foldersTable' table exists.");

        var columnInfo = await db.rawQuery("PRAGMA table_info($_flashcardsTable)");
        bool folderColumnExists = columnInfo.any((col) => col['name'] == _colFolderId);
        if (!folderColumnExists) {
          await db.execute(
            'ALTER TABLE $_flashcardsTable ADD COLUMN $_colFolderId INTEGER REFERENCES $_foldersTable($_colId) ON DELETE CASCADE'
          );
          print("Added '$_colFolderId' column to '$_flashcardsTable'.");
        } else {
           print("'$_colFolderId' column already exists in '$_flashcardsTable'.");
        }
        print("Database upgrade (v1->v2) completed successfully.");
      } catch (e) {
        print("Error during database upgrade from v1 to v2: $e");
        rethrow;
      }
    }
    if (oldVersion < 3) {
       try {
         print("Applying migration v2 -> v3 (Spaced Repetition)...");
         // ... (migration v2 -> v3 code remains the same) ...
         await db.transaction((txn) async {
             await _addColumnIfNotExists(txn, _flashcardsTable, _colEasinessFactor, 'REAL DEFAULT 2.5');
             await _addColumnIfNotExists(txn, _flashcardsTable, _colInterval, 'INTEGER DEFAULT 0');
             await _addColumnIfNotExists(txn, _flashcardsTable, _colRepetitions, 'INTEGER DEFAULT 0');
             await _addColumnIfNotExists(txn, _flashcardsTable, _colLastReviewed, 'TEXT');
             await _addColumnIfNotExists(txn, _flashcardsTable, _colNextReview, 'TEXT');
         });
         print("Database upgrade (v2->v3) completed successfully.");
       } catch (e) {
          print("Error during database upgrade from v2 to v3: $e");
          rethrow;
       }
    }
    // Add new migration step for version 4
    if (oldVersion < 4) {
      try {
        print("Applying migration v3 -> v4 (Last Rating Quality)...");
        await db.transaction((txn) async {
          await _addColumnIfNotExists(txn, _flashcardsTable, _colLastRatingQuality, 'INTEGER'); // Nullable integer
        });
        print("Database upgrade (v3->v4) completed successfully.");
      } catch (e) {
        print("Error during database upgrade from v3 to v4: $e");
        rethrow;
      }
    }
  }

  Future<void> _addColumnIfNotExists(Transaction txn, String tableName, String columnName, String columnDefinition) async {
      var result = await txn.rawQuery("PRAGMA table_info($tableName)");
      bool columnExists = result.any((col) => col['name'] == columnName);
      if (!columnExists) {
          await txn.execute('ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition');
          print("Added '$columnName' column to '$tableName'.");
      } else {
          print("Column '$columnName' already exists in '$tableName'.");
      }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    print("Foreign key support enabled.");
  }

  Future<void> closeDatabase() async {
     if (_dbOpenCompleter != null && _dbOpenCompleter!.isCompleted) {
       try {
         final db = await _dbOpenCompleter!.future;
         if (db.isOpen) {
           await db.close();
           print("Database closed.");
         }
       } catch (e) {
         print("Error closing database: $e");
       } finally {
         _dbOpenCompleter = null;
       }
     }
   }

  // --- CRUD Operations ---

  // Modified getFlashcards (no specific column selection needed as * includes all)
  Future<List<Flashcard>> getFlashcards({int? folderId}) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        _flashcardsTable,
        orderBy: "$_colId ASC",
        where: folderId == null ? '$_colFolderId IS NULL' : '$_colFolderId = ?',
        whereArgs: folderId == null ? null : [folderId],
      );
      // Flashcard.fromMap will handle the new column
      return List.generate(maps.length, (i) => Flashcard.fromMap(maps[i]));
    } catch (e) {
        print("Error fetching flashcards (folderId: $folderId): $e");
        throw Exception('Failed to load flashcards: $e');
    }
  }

  Future<int> insertFlashcard(Flashcard flashcard) async {
    final db = await database;
    // toMap now includes lastRatingQuality (which will be null initially)
    Map<String, dynamic> map = flashcard.toMap()..remove(_colId);
    try {
      return await db.insert(
        _flashcardsTable,
        map,
        conflictAlgorithm: ConflictAlgorithm.abort
      );
    } catch (e) {
       print("Error inserting flashcard (${flashcard.question}): $e");
       throw Exception('Failed to save flashcard: $e');
    }
  }

  Future<int> updateFlashcard(Flashcard flashcard) async {
    final db = await database;
    ArgumentError.checkNotNull(flashcard.id, 'flashcard.id cannot be null for update');
    try {
      return await db.update(
        _flashcardsTable,
        flashcard.toMap(), // toMap now includes SR fields and lastRatingQuality
        where: '$_colId = ?',
        whereArgs: [flashcard.id],
      );
    } catch (e) {
        print("Error updating flashcard (ID: ${flashcard.id}): $e");
        throw Exception('Failed to update flashcard: $e');
    }
  }

  Future<int> deleteFlashcard(int id) async {
    final db = await database;
    int affectedRows = 0;
    try {
      affectedRows = await db.delete(
        _flashcardsTable,
        where: '$_colId = ?',
        whereArgs: [id],
      );
      if (affectedRows > 0) {
        await _persistenceService.clearChecklistState(id);
        print("Deleted flashcard (ID: $id) and cleared its checklist state.");
      } else {
         print("Warning: Attempted to delete non-existent flashcard (ID: $id).");
      }
    } catch (e) {
      print("Error deleting flashcard (ID: $id): $e");
      throw Exception('Failed to delete flashcard: $e');
    }
    return affectedRows;
  }

  Future<void> moveFlashcards(List<int> cardIds, int? newFolderId) async {
    if (cardIds.isEmpty) return;
    final db = await database;
    try {
      await db.transaction((txn) async {
        String placeholders = List.filled(cardIds.length, '?').join(',');
        await txn.update(
          _flashcardsTable,
          {_colFolderId: newFolderId},
          where: '$_colId IN ($placeholders)',
          whereArgs: cardIds,
        );
      });
      print("Moved ${cardIds.length} flashcards to folder ID: $newFolderId");
    } catch (e) {
        print("Error moving ${cardIds.length} flashcards to folder ID $newFolderId: $e");
        throw Exception('Failed to move flashcards: $e');
    }
  }

  Future<void> copyFlashcards(List<int> cardIds, int? destinationFolderId) async {
    if (cardIds.isEmpty) return;
    final db = await database;
    try {
      String placeholders = List.filled(cardIds.length, '?').join(',');
      final List<Map<String, dynamic>> originalMaps = await db.query(
        _flashcardsTable,
        where: '$_colId IN ($placeholders)',
        whereArgs: cardIds,
      );

      if (originalMaps.isEmpty) {
          print("Warning: No flashcards found to copy for IDs: $cardIds");
          return;
      }

      final List<Flashcard> originalCards = List.generate(originalMaps.length, (i) => Flashcard.fromMap(originalMaps[i]));

      final List<Flashcard> copiedCards = originalCards.map((original) {
        // Reset SR data and last rating quality for the copy
        return Flashcard(
          question: original.question,
          answer: original.answer,
          folderId: destinationFolderId,
          easinessFactor: 2.5,
          interval: 0,
          repetitions: 0,
          lastReviewed: null,
          nextReview: null,
          lastRatingQuality: null, // Ensure copy starts fresh
        );
      }).toList();

      await db.transaction((txn) async {
        for (var card in copiedCards) {
          await txn.insert(_flashcardsTable, card.toMap()..remove(_colId), conflictAlgorithm: ConflictAlgorithm.abort);
        }
      });
      print("Copied ${copiedCards.length} flashcards to folder ID: $destinationFolderId");

    } catch (e) {
       print("Error copying flashcards (IDs: $cardIds) to folder ID $destinationFolderId: $e");
       throw Exception('Failed to copy flashcards: $e');
    }
  }

  // --- Folder CRUD (Unchanged) ---
  Future<List<Folder>> getFolders({int? parentId}) async { /* ... existing code ... */
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        _foldersTable,
        where: parentId == null ? '$_colParentId IS NULL' : '$_colParentId = ?',
        whereArgs: parentId == null ? null : [parentId],
        orderBy: '$_colName COLLATE NOCASE ASC',
      );
      return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
    } catch (e) {
       print("Error fetching folders (parentId: $parentId): $e");
       throw Exception('Failed to load folders: $e');
    }
  }
  Future<List<Folder>> getAllFolders() async { /* ... existing code ... */
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        _foldersTable,
        orderBy: '$_colName COLLATE NOCASE ASC'
      );
      return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
    } catch (e) {
       print("Error fetching all folders: $e");
       throw Exception('Failed to load all folders: $e');
    }
   }
  Future<Folder?> getFolderById(int folderId) async { /* ... existing code ... */
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        _foldersTable,
        where: '$_colId = ?',
        whereArgs: [folderId],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return Folder.fromMap(maps.first);
      }
      return null;
    } catch (e) {
       print("Error fetching folder by ID ($folderId): $e");
       throw Exception('Failed to load folder: $e');
    }
   }
  Future<List<Folder>> getFolderPath(int? folderId) async { /* ... existing code ... */
    if (folderId == null) return [];
    final List<Folder> path = [];
    int? currentId = folderId;
    try {
      while (currentId != null) {
        final folder = await getFolderById(currentId);
        if (folder != null) {
          path.add(folder);
          currentId = folder.parentId;
        } else {
          print("Warning: Could not find folder with ID $currentId while building path for $folderId.");
          break;
        }
      }
      return path.reversed.toList();
    } catch (e) {
       print("Error getting folder path for ID ($folderId): $e");
       throw Exception('Failed to retrieve folder path: $e');
    }
  }
  Future<int> insertFolder(Folder folder) async { /* ... existing code ... */
    final db = await database;
    Map<String, dynamic> map = folder.toMap()..remove(_colId);
    try {
      return await db.insert(_foldersTable, map, conflictAlgorithm: ConflictAlgorithm.abort);
    } catch (e) {
       print("Error inserting folder (${folder.name}): $e");
       throw Exception('Failed to save folder: $e');
    }
  }
  Future<int> updateFolder(Folder folder) async { /* ... existing code ... */
    final db = await database;
    ArgumentError.checkNotNull(folder.id, 'folder.id cannot be null for update');
    try {
      return await db.update(
        _foldersTable,
        folder.toMap(),
        where: '$_colId = ?',
        whereArgs: [folder.id],
      );
    } catch (e) {
        print("Error updating folder (ID: ${folder.id}, Name: ${folder.name}): $e");
        throw Exception('Failed to update folder: $e');
    }
  }
  Future<int> deleteFolder(int id) async { /* ... existing code ... */
    final db = await database;
    try {
      int affectedRows = await db.delete(
        _foldersTable,
        where: '$_colId = ?',
        whereArgs: [id],
      );
       if (affectedRows > 0) {
          print("Deleted folder (ID: $id) and its contents (due to CASCADE).");
       } else {
          print("Warning: Attempted to delete non-existent folder (ID: $id).");
       }
      return affectedRows;
    } catch (e) {
      print("Error deleting folder (ID: $id): $e");
      throw Exception('Failed to delete folder: $e');
    }
  }

  // --- Spaced Repetition Methods ---

  // Modified updateFlashcardReviewData
  /// Updates the spaced repetition data and last rating quality for a specific flashcard.
  Future<int> updateFlashcardReviewData(int cardId, {
    required double easinessFactor,
    required int interval,
    required int repetitions,
    required DateTime? lastReviewed, // Nullable in case SR resets
    required DateTime? nextReview,   // Nullable in case SR resets
    required int? lastRatingQuality, // Added: Quality rating (0-5) submitted
  }) async {
    final db = await database;
    try {
      final Map<String, dynamic> dataToUpdate = {
        _colEasinessFactor: easinessFactor,
        _colInterval: interval,
        _colRepetitions: repetitions,
        _colLastReviewed: lastReviewed?.toIso8601String(), // Store as ISO string or null
        _colNextReview: nextReview?.toIso8601String(),     // Store as ISO string or null
        _colLastRatingQuality: lastRatingQuality,           // Store the rating quality
      };

      print("Updating SR data for card ID $cardId: $dataToUpdate"); // Debug log

      return await db.update(
        _flashcardsTable,
        dataToUpdate,
        where: '$_colId = ?',
        whereArgs: [cardId],
      );
    } catch (e) {
      print("Error updating SR data for card ID $cardId: $e");
      throw Exception('Failed to update review data: $e');
    }
  }

  // Modified getDueFlashcards (no specific column selection needed)
  /// Fetches flashcards from a specific folder (or uncategorized)
  /// that are due for review (nextReview <= now).
  Future<List<Flashcard>> getDueFlashcards({int? folderId, required DateTime now}) async {
    final db = await database;
    try {
      final String nowString = now.toIso8601String();
      final List<Map<String, dynamic>> maps = await db.query(
        _flashcardsTable,
        where: '${_buildFolderFilter(folderId)} AND ($_colNextReview IS NOT NULL AND $_colNextReview <= ?)',
        whereArgs: folderId == null ? [nowString] : [folderId, nowString],
        orderBy: "$_colNextReview ASC",
      );
       print("Found ${maps.length} due cards for folder $folderId at $nowString"); // Debug log
      // Flashcard.fromMap will handle the new column
      return List.generate(maps.length, (i) => Flashcard.fromMap(maps[i]));
    } catch (e) {
      print("Error fetching due flashcards (folderId: $folderId): $e");
      throw Exception('Failed to load due flashcards: $e');
    }
  }

  /// Helper to build the folder part of the WHERE clause.
  String _buildFolderFilter(int? folderId) {
     return folderId == null ? '$_colFolderId IS NULL' : '$_colFolderId = ?';
  }

}