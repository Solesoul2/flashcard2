// lib/providers/csv_import_notifier.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart'; // For Color
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart'; // For ConflictAlgorithm

import '../models/flashcard.dart';
import '../models/folder.dart';
import '../providers/service_providers.dart'; // Access DatabaseHelper provider

// State class to hold UI state for the import process
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
  final Folder _folder; // Folder context for import

  CsvImportNotifier(this._ref, this._folder) : super(const CsvImportState());

  // Select CSV File Logic
  Future<void> selectCsvFile() async {
    if (state.isImporting) return;

    // Reset state before picking
    state = const CsvImportState();

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        // Use utf8.decode with allowMalformed: true for robustness
        final content = utf8.decode(bytes, allowMalformed: true);

        state = state.copyWith(
          csvFileContent: content,
          selectedFileName: result.files.single.name,
          statusMessage: "File selected: ${result.files.single.name}. Ready to import.",
          statusColor: Colors.black87,
        );
      } else {
        state = state.copyWith(
          statusMessage: "File selection cancelled.",
          statusColor: Colors.orange,
        );
      }
    } catch (e) {
      print("Error picking or reading file: $e");
      state = state.copyWith(
        statusMessage: 'Error selecting file: ${e.toString()}',
        statusColor: Colors.red[700]!,
        isImporting: false, // Ensure importing is false on error
      );
    }
  }

  // Parse CSV Content (internal helper)
  // Returns parsed cards and the count of skipped rows
  ({List<Flashcard> cards, int skippedCount}) _parseCsv(String content) {
    final List<Flashcard> cards = [];
    int skipped = 0;
    List<List<dynamic>> rows;

    try {
      // Allow invalid lines, don't parse numbers automatically
      rows = const CsvToListConverter(shouldParseNumbers: false, allowInvalid: true)
             .convert(content);
    } catch (e) {
      print("Error converting CSV content: $e");
      // Re-throw a more user-friendly exception if needed, caught by importCsv
      throw Exception('Failed to parse CSV structure. Please check format. Error: $e');
    }

    bool isFirstRow = true; // Simple header detection
    int rowNum = 0;
    for (final row in rows) {
      rowNum++;
      // Basic header check: skip if first row and first cell is "question" (case-insensitive)
      if (isFirstRow && row.isNotEmpty && row[0].toString().trim().toLowerCase() == "question") {
         isFirstRow = false;
         print("Skipping potential header row: $row");
         continue;
      }
      isFirstRow = false; // Don't check header again

      // Check for sufficient columns (at least 2)
      if (row.length < 2) {
         print("Skipping CSV row #$rowNum (insufficient columns): $row");
         skipped++;
         continue;
      }

      // Trim and validate question and answer
      final String question = row[0]?.toString().trim() ?? '';
      final String answer = row[1]?.toString().trim() ?? '';

      if (question.isEmpty || answer.isEmpty) {
         print("Skipping CSV row #$rowNum (empty question or answer): $row");
         skipped++;
         continue;
      }

      // Create Flashcard object (without ID, folderId assigned later)
      cards.add(Flashcard(question: question, answer: answer));
    }

    return (cards: cards, skippedCount: skipped);
  }

  // Import CSV Logic
  Future<void> importCsv() async {
    if (state.csvFileContent.isEmpty) {
      state = state.copyWith(statusMessage: 'Please select a CSV file first.', statusColor: Colors.orange);
      return;
    }
    if (state.isImporting) return;

    state = state.copyWith(isImporting: true, statusMessage: 'Importing...', statusColor: Colors.blue, skippedRowCount: 0);

    try {
      // 1. Parse CSV
      final parseResult = _parseCsv(state.csvFileContent);
      final cardsToImport = parseResult.cards;
      final currentSkippedCount = parseResult.skippedCount;

      // Update skipped count immediately after parsing
      state = state.copyWith(skippedRowCount: currentSkippedCount);

      if (cardsToImport.isEmpty) {
         state = state.copyWith(
           statusMessage: 'No valid flashcards found to import.' + (currentSkippedCount > 0 ? ' ($currentSkippedCount rows skipped)' : ''),
           statusColor: currentSkippedCount > 0 ? Colors.orange : Colors.green[700]!,
           isImporting: false,
           csvFileContent: "", // Clear content after processing
           clearSelectedFileName: true, // Clear filename
         );
         return;
      }

      // 2. Get Database Helper
      final dbHelper = await _ref.read(databaseHelperProvider.future);
      final db = await dbHelper.database;

      // 3. Insert into Database within a Transaction
      int insertedCount = 0;
      await db.transaction((txn) async {
         // Use constant from DatabaseHelper if accessible, otherwise string literal
         const String tableName = 'flashcards';
         for (final card in cardsToImport) {
           await txn.insert(
             tableName,
             Flashcard(
                question: card.question,
                answer: card.answer,
                folderId: _folder.id, // Assign folderId here
              ).toMap()..remove('id'), // Ensure ID is null for insert
             conflictAlgorithm: ConflictAlgorithm.abort,
           );
           insertedCount++;
         }
      });

      // 4. Update State on Success
      state = state.copyWith(
        statusMessage: 'Successfully imported $insertedCount flashcard(s).' + (currentSkippedCount > 0 ? ' ($currentSkippedCount rows skipped)' : ''),
        statusColor: Colors.green[700]!,
        isImporting: false,
        csvFileContent: "", // Clear content
        clearSelectedFileName: true, // Clear filename
      );

    } catch (e) {
      print("Error during CSV import process: $e");
      // 5. Update State on Error
      state = state.copyWith(
        // Provide clearer error message extraction
        statusMessage: 'Import Error: ${e.toString().replaceFirst("Exception: ", "")}',
        statusColor: Colors.red[700]!,
        isImporting: false,
        // Optionally keep content/filename on error for retry? Or clear? Clearing for now.
        // csvFileContent: "",
        // clearSelectedFileName: true,
      );
    }
  }
}

// Provider definition (using StateNotifierProvider)
// Using .autoDispose if the state should reset when the page is left
final csvImportProvider = StateNotifierProvider.autoDispose.family<CsvImportNotifier, CsvImportState, Folder>((ref, folder) {
  return CsvImportNotifier(ref, folder);
});