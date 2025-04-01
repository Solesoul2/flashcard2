// lib/providers/csv_import_notifier.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/material.dart'; // For Color
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart'; // For ConflictAlgorithm

import '../models/flashcard.dart';
import '../models/folder.dart';
import '../providers/service_providers.dart'; // Access DatabaseHelper provider
import '../services/database_helper.dart'; // Import for table name constants etc.

// State class remains the same
@immutable
class CsvImportState {
  final String statusMessage;
  final Color statusColor;
  final String? selectedFileName;
  final String csvFileContent; // Keep content needed for import
  final bool isImporting;
  final int skippedRowCount;

  const CsvImportState({
    this.statusMessage = "Select a CSV file to import.",
    this.statusColor = Colors.black87,
    this.selectedFileName,
    this.csvFileContent = "",
    this.isImporting = false,
    this.skippedRowCount = 0,
  });

  CsvImportState copyWith({
    String? statusMessage,
    Color? statusColor,
    String? selectedFileName,
    bool clearSelectedFileName = false, // Flag to explicitly clear filename
    String? csvFileContent,
    bool? isImporting,
    int? skippedRowCount,
  }) {
    return CsvImportState(
      statusMessage: statusMessage ?? this.statusMessage,
      statusColor: statusColor ?? this.statusColor,
      selectedFileName: clearSelectedFileName ? null : selectedFileName ?? this.selectedFileName,
      csvFileContent: csvFileContent ?? this.csvFileContent,
      isImporting: isImporting ?? this.isImporting,
      skippedRowCount: skippedRowCount ?? this.skippedRowCount,
    );
  }
}

// Notifier to manage the CsvImportState
class CsvImportNotifier extends StateNotifier<CsvImportState> {
  final Ref _ref;
  final Folder _folder; // The parent folder under which new subfolders will be created

  CsvImportNotifier(this._ref, this._folder) : super(const CsvImportState());

  // Select CSV File Logic (remains the same)
  Future<void> selectCsvFile() async {
    if (state.isImporting) return;
    state = const CsvImportState(); // Reset state
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv'],
      );
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: true);
        state = state.copyWith(
          csvFileContent: content,
          selectedFileName: result.files.single.name,
          statusMessage: "File selected: ${result.files.single.name}. Ready to import.",
          statusColor: Colors.black87,
        );
      } else {
        state = state.copyWith(statusMessage: "File selection cancelled.", statusColor: Colors.orange);
      }
    } catch (e) {
      print("Error picking or reading file: $e");
      state = state.copyWith(
        statusMessage: 'Error selecting file: ${e.toString()}',
        statusColor: Colors.red[700]!,
        isImporting: false,
      );
    }
  }

  // Parse CSV Content (remains the same from previous version)
  ({List<List<Flashcard>> cardSets, int skippedCount}) _parseCsv(String content) {
    print("--- Starting CSV Parsing ---");
    final List<List<Flashcard>> cardSets = [];
    List<Flashcard> currentSet = [];
    int skipped = 0;
    List<List<dynamic>> rows;

    try {
      rows = const CsvToListConverter(
              shouldParseNumbers: false, allowInvalid: true, eol: '\n')
          .convert(content.replaceAll('\r\n', '\n'), eol: '\n');
      print("CSV Parsing: Converted content to ${rows.length} rows.");
    } catch (e) {
      print("CSV Parsing Error: Failed during CsvToListConverter: $e");
      throw Exception('Failed to parse CSV structure. Please check format. Error: $e');
    }

    bool isFirstRow = true;
    int rowNum = 0;
    for (final row in rows) {
      rowNum++;
      if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
        print("  -> Skipping empty row #$rowNum.");
        skipped++;
        continue;
      }

      bool isDelimiter = false;
      if (row.length >= 2) {
        final col1 = row[0]?.toString().trim() ?? '';
        final col2 = row[1]?.toString().trim() ?? '';
        if (col1.toLowerCase() == 'question' && col2.toLowerCase() == 'answer') {
          print("  -> Detected DELIMITER at row #$rowNum: $row");
          isDelimiter = true;
          if (currentSet.isNotEmpty) {
            print("     -> Finalizing previous set with ${currentSet.length} cards.");
            cardSets.add(List.from(currentSet));
            currentSet.clear();
          } else {
             print("     -> Delimiter found, but previous set was empty. Ignoring.");
          }
        }
      }

      if (isDelimiter) {
        isFirstRow = false;
        continue;
      }

      if (isFirstRow && row.isNotEmpty) {
         final col1 = row[0]?.toString().trim() ?? '';
         if (col1.toLowerCase() == 'question') {
           print("  -> Skipping potential HEADER row #$rowNum: $row");
           isFirstRow = false;
           skipped++;
           continue;
         }
      }
      isFirstRow = false;

      if (row.length < 2) {
         print("  -> Skipping row #$rowNum (insufficient columns: ${row.length}): $row");
         skipped++;
         continue;
      }

      final String question = row[0]?.toString().trim() ?? '';
      final String answer = row[1]?.toString().trim() ?? '';

      if (question.isEmpty || answer.isEmpty) {
         print("  -> Skipping row #$rowNum (empty question or answer): Q='${question}', A='${answer}' | Original row: $row");
         skipped++;
         continue;
      }
      currentSet.add(Flashcard(question: question, answer: answer));
    } // End row loop

    if (currentSet.isNotEmpty) {
      print("Finalizing last set with ${currentSet.length} cards.");
      cardSets.add(List.from(currentSet));
    } else {
       print("Last set was empty, not adding.");
    }

    print("--- CSV Parsing Finished ---");
    print("Found ${cardSets.length} sets of cards. Total skipped rows: $skipped");
    if (cardSets.isNotEmpty) {
        for(int i=0; i < cardSets.length; i++) {
            print("Set ${i+1} has ${cardSets[i].length} cards.");
        }
    }
    return (cardSets: cardSets, skippedCount: skipped);
  }


  // *** REVISED: Import CSV Logic ***
  Future<void> importCsv() async {
    if (state.csvFileContent.isEmpty) {
      state = state.copyWith(statusMessage: 'Please select a CSV file first.', statusColor: Colors.orange);
      return;
    }
    if (state.isImporting) return;

    state = state.copyWith(isImporting: true, statusMessage: 'Importing...', statusColor: Colors.blue, skippedRowCount: 0);
    int totalInsertedCount = 0;
    int foldersCreatedCount = 0;
    int skippedRowCount = 0;

    print("--- Starting CSV Import Process ---");
    // The initial folder is now always the PARENT for the new subfolders
    print("Parent folder for new imports: Name='${_folder.name}', ID=${_folder.id}");

    try {
      // 1. Parse CSV
      final parseResult = _parseCsv(state.csvFileContent);
      final List<List<Flashcard>> cardSets = parseResult.cardSets;
      skippedRowCount = parseResult.skippedCount; // Get skipped count from parsing

      state = state.copyWith(skippedRowCount: skippedRowCount);
      print("Parsing step complete. Skipped rows: $skippedRowCount. Card sets found: ${cardSets.length}");

      if (cardSets.isEmpty) {
         print("No valid card sets found after parsing.");
         state = state.copyWith(
           statusMessage: 'No valid flashcards found to import.' + (skippedRowCount > 0 ? ' ($skippedRowCount rows skipped)' : ''),
           statusColor: skippedRowCount > 0 ? Colors.orange : Colors.green[700]!,
           isImporting: false,
           csvFileContent: "", clearSelectedFileName: true,
         );
         return;
      }

      // Check if the initial folder can be a parent
      if (_folder.id == null) {
         print("Import Error: Cannot import into 'Uncategorized'. Please select a specific folder to import into.");
         state = state.copyWith(
             statusMessage: "Error: Cannot import into 'Uncategorized'. Select a folder.",
             statusColor: Colors.red[700]!,
             isImporting: false);
         return;
      }
      final int parentFolderId = _folder.id!; // We know it's not null here

      // 2. Get Database Helper
      final dbHelper = await _ref.read(databaseHelperProvider.future);
      final db = await dbHelper.database;

      // 3. Process each set within a transaction
      print("Starting database transaction...");
      await db.transaction((txn) async {
         final String flashcardsTable = DatabaseHelper.flashcardsTable;
         final String foldersTable = DatabaseHelper.foldersTable;
         int? newlyCreatedFolderId; // Will hold the ID for the current set's folder

         for (int i = 0; i < cardSets.length; i++) {
           final cardSet = cardSets[i];
           print("\nProcessing Set ${i + 1}/${cardSets.length} with ${cardSet.length} cards.");

           if (cardSet.isEmpty) {
              print("  -> Skipping empty card set at index $i.");
              continue;
           }

           // *** ALWAYS Create a new subfolder for EVERY set ***
           final subfolderName = "Imported Set ${i + 1}"; // 1-based index for name
           print("  -> Attempting to create subfolder '$subfolderName' under parent ID: $parentFolderId");
           try {
              final newFolderData = Folder(name: subfolderName, parentId: parentFolderId).toMap()..remove('id');
              newlyCreatedFolderId = await txn.insert(foldersTable, newFolderData, conflictAlgorithm: ConflictAlgorithm.replace); // Use replace to handle retries
              foldersCreatedCount++;
              print("     -> Subfolder '$subfolderName' created/replaced with ID: $newlyCreatedFolderId");
           } catch (folderError, stackTrace) {
              print("     -> *** ERROR creating subfolder '$subfolderName': $folderError");
              print("        Stack trace: $stackTrace");
              print("     -> Skipping card insertion for this set (Set ${i+1}).");
              newlyCreatedFolderId = null; // Prevent insertion for this set
              continue; // Skip to the next cardSet
           }

           // Insert cards for the current set IF folder creation was successful
           if (newlyCreatedFolderId == null) {
               print("  -> Skipping card insertion for Set ${i+1} due to missing target folder ID (creation failed).");
               continue;
           }

           print("  -> Inserting ${cardSet.length} cards into target folder ID: $newlyCreatedFolderId");
           int setInsertedCount = 0;
           for (final card in cardSet) {
             try {
               await txn.insert(
                 flashcardsTable,
                 Flashcard(
                    question: card.question,
                    answer: card.answer,
                    folderId: newlyCreatedFolderId, // Use the NEWLY created folder ID
                  ).toMap()..remove('id'),
                 conflictAlgorithm: ConflictAlgorithm.abort,
               );
               setInsertedCount++;
             } catch (cardInsertError) {
                 print("     -> *** ERROR inserting card: Q='${card.question.substring(0, min(card.question.length, 20))}'... Error: $cardInsertError");
             }
           }
           print("  -> Successfully inserted $setInsertedCount cards for Set ${i + 1}.");
           totalInsertedCount += setInsertedCount;

         } // End loop through cardSets
         print("\nDatabase transaction finishing.");
      }); // End transaction
      print("Database transaction committed successfully.");

      // 4. Update State on Success
      String successMessage = 'Import finished. $totalInsertedCount flashcard(s) imported';
      if (foldersCreatedCount > 0) {
         // Always creating subfolders now, so this message is more accurate
         successMessage += ' into $foldersCreatedCount new subfolder(s) under "${_folder.name}"';
      }
      if (skippedRowCount > 0) {
          successMessage += '. ($skippedRowCount rows skipped)';
      }
       successMessage += '.';

      print("--- CSV Import Process Finished Successfully ---");
      print("Final Status: $successMessage");


      state = state.copyWith(
        statusMessage: successMessage,
        statusColor: Colors.green[700]!,
        isImporting: false,
        csvFileContent: "", // Clear content
        clearSelectedFileName: true, // Clear filename
      );

    } catch (e, stackTrace) { // Catch errors from parsing or transaction
      print("\n--- CSV Import Process FAILED ---");
      print("Error during CSV import process: $e");
      print("Stack trace: $stackTrace");
      // 5. Update State on Error
      state = state.copyWith(
        statusMessage: 'Import Error: ${e.toString().replaceFirst("Exception: ", "")}',
        statusColor: Colors.red[700]!,
        isImporting: false,
      );
    }
  }
}

// Provider definition (remains the same)
final csvImportProvider = StateNotifierProvider.autoDispose.family<CsvImportNotifier, CsvImportState, Folder>((ref, folder) {
  return CsvImportNotifier(ref, folder);
});