// lib/providers/folder_detail_notifier.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../models/flashcard.dart';
import '../providers/service_providers.dart'; // Import service providers

// State class remains the same
@immutable
class FolderDetailState {
  final List<Folder> subfolders;
  final List<Flashcard> flashcards;
  final bool isCardSelectionMode;
  final Set<int> selectedCardIds;
  final Folder currentFolder;

  const FolderDetailState({
    required this.currentFolder,
    this.subfolders = const [],
    this.flashcards = const [],
    this.isCardSelectionMode = false,
    this.selectedCardIds = const {},
  });

  FolderDetailState copyWith({
    List<Folder>? subfolders,
    List<Flashcard>? flashcards,
    bool? isCardSelectionMode,
    Set<int>? selectedCardIds,
    Folder? currentFolder,
  }) {
    return FolderDetailState(
      currentFolder: currentFolder ?? this.currentFolder,
      subfolders: subfolders ?? this.subfolders,
      flashcards: flashcards ?? this.flashcards,
      isCardSelectionMode: isCardSelectionMode ?? this.isCardSelectionMode,
      selectedCardIds: selectedCardIds ?? this.selectedCardIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderDetailState &&
          runtimeType == other.runtimeType &&
          currentFolder == other.currentFolder &&
          listEquals(subfolders, other.subfolders) &&
          listEquals(flashcards, other.flashcards) &&
          isCardSelectionMode == other.isCardSelectionMode &&
          setEquals(selectedCardIds, other.selectedCardIds);

  @override
  int get hashCode =>
      currentFolder.hashCode ^
      Object.hashAll(subfolders) ^
      Object.hashAll(flashcards) ^
      isCardSelectionMode.hashCode ^
      Object.hashAll(selectedCardIds);
}

// --- FolderDetailNotifier ---

class FolderDetailNotifier extends FamilyAsyncNotifier<FolderDetailState, Folder> {

  @override
  Future<FolderDetailState> build(Folder arg /* currentFolder */) async {
    final currentFolder = arg;
    if (currentFolder.id == null && currentFolder.name != "Uncategorized") {
      throw Exception("Error: Invalid folder context provided to FolderDetailNotifier.");
    }

    final dbHelper = await ref.read(databaseHelperProvider.future);
    // Pass dbHelper to the fetch method
    final results = await _fetchFolderContents(dbHelper, currentFolder.id);

    return FolderDetailState(
      currentFolder: currentFolder,
      subfolders: results.subfolders,
      flashcards: results.flashcards,
      isCardSelectionMode: false,
      selectedCardIds: {},
    );
  }

  // --- Private Helper to Fetch Data ---
  Future<({List<Folder> subfolders, List<Flashcard> flashcards})> _fetchFolderContents(
      /* await ref.read(databaseHelperProvider.future) */ dbHelper, // dbHelper is passed in
      int? folderId) async {

    // Explicitly type the Futures
    final Future<List<Folder>> subfoldersFuture = folderId == null
        ? Future.value(<Folder>[])
        : dbHelper.getFolders(parentId: folderId);

    final Future<List<Flashcard>> flashcardsFuture = dbHelper.getFlashcards(folderId: folderId);

    // Explicitly type the list passed to Future.wait
    final List<Object> results = await Future.wait<Object>( // Or Future.wait<dynamic>
        <Future<Object>>[subfoldersFuture, flashcardsFuture]
    );

    // Cast results after awaiting
    return (subfolders: results[0] as List<Folder>, flashcards: results[1] as List<Flashcard>);
  }

  // --- Public Methods ---

  Future<void> refreshContent() async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = const AsyncLoading();
    try {
      final dbHelper = await ref.read(databaseHelperProvider.future);
      // Pass dbHelper to the fetch method
      final results = await _fetchFolderContents(dbHelper, currentState.currentFolder.id);
      state = AsyncData(currentState.copyWith(
        subfolders: results.subfolders,
        flashcards: results.flashcards,
        isCardSelectionMode: false, // Always reset selection on refresh
        selectedCardIds: {},
      ));
    } catch (e, stack) {
      print("Error refreshing folder content: $e");
      state = AsyncError(e, stack);
    }
  }

  // --- Card Selection Methods (Now defined only once) ---
   void enterCardSelectionMode(int cardId) {
     state.whenData((data) {
       if (!data.isCardSelectionMode) {
         state = AsyncData(data.copyWith(
           isCardSelectionMode: true,
           selectedCardIds: {cardId},
         ));
       }
     });
   }
   void cancelCardSelection() {
     state.whenData((data) {
       if (data.isCardSelectionMode) {
         state = AsyncData(data.copyWith(
           isCardSelectionMode: false,
           selectedCardIds: {},
         ));
       }
     });
   }
   void toggleCardSelection(int cardId) {
     state.whenData((data) {
       if (!data.isCardSelectionMode) return;
       final newSelection = Set<int>.from(data.selectedCardIds);
       if (newSelection.contains(cardId)) {
         newSelection.remove(cardId);
       } else {
         newSelection.add(cardId);
       }
       final newMode = newSelection.isNotEmpty;
       state = AsyncData(data.copyWith(
         selectedCardIds: newSelection,
         isCardSelectionMode: newMode,
       ));
     });
   }

   // --- Subfolder Action Methods (Now defined only once) ---
   Future<void> addSubfolder(String name) async {
     final currentState = state.valueOrNull;
     if (currentState == null || currentState.currentFolder.id == null) {
        throw Exception("Cannot add subfolder here.");
     }
     try {
       final dbHelper = await ref.read(databaseHelperProvider.future);
       await dbHelper.insertFolder(Folder(name: name, parentId: currentState.currentFolder.id));
       await refreshContent();
     } catch (e) {
        print("Error adding subfolder: $e");
        throw Exception("Failed to add subfolder: $e");
     }
   }

   Future<void> renameFolder(Folder folderToRename, String newName) async {
      if (folderToRename.id == null || newName.trim().isEmpty || newName == folderToRename.name) {
          return;
      }
      try {
          final dbHelper = await ref.read(databaseHelperProvider.future);
          await dbHelper.updateFolder(folderToRename.copyWith(name: newName));
          await refreshContent();
          final refreshedState = state.valueOrNull;
          if (refreshedState != null && refreshedState.currentFolder.id == folderToRename.id) {
              state = AsyncData(refreshedState.copyWith(
                  currentFolder: refreshedState.currentFolder.copyWith(name: newName)
              ));
          }
      } catch (e) {
          print("Error renaming folder: $e");
          throw Exception("Failed to rename folder: $e");
      }
    }

   Future<void> deleteSubfolder(int folderId) async {
     try {
        final dbHelper = await ref.read(databaseHelperProvider.future);
        await dbHelper.deleteFolder(folderId);
        await refreshContent();
     } catch (e) {
        print("Error deleting subfolder: $e");
        throw Exception("Failed to delete subfolder: $e");
     }
   }

   // --- Flashcard Action Methods (Now defined only once) ---
   Future<void> addFlashcard(String question, String answer) async {
      final currentState = state.valueOrNull;
      if (currentState == null) return;
      try {
          final dbHelper = await ref.read(databaseHelperProvider.future);
          final newCard = Flashcard(
              question: question,
              answer: answer,
              folderId: currentState.currentFolder.id
          );
          await dbHelper.insertFlashcard(newCard);
          await refreshContent();
      } catch (e) {
          print("Error adding flashcard: $e");
          throw Exception("Failed to add flashcard: $e");
      }
    }

   Future<void> updateFlashcard(Flashcard originalCard, String newQuestion, String newAnswer) async {
      if (originalCard.id == null) return;
      try {
          final dbHelper = await ref.read(databaseHelperProvider.future);
          final updatedCard = originalCard.copyWith(
              question: newQuestion,
              answer: newAnswer
          );
          await dbHelper.updateFlashcard(updatedCard);
          await refreshContent();
      } catch (e) {
          print("Error updating flashcard: $e");
          throw Exception("Failed to update flashcard: $e");
      }
    }

   Future<void> deleteFlashcard(int cardId) async {
     try {
       final dbHelper = await ref.read(databaseHelperProvider.future);
       await dbHelper.deleteFlashcard(cardId);
       await refreshContent();
     } catch (e) {
       print("Error deleting flashcard: $e");
       throw Exception("Failed to delete flashcard: $e");
     }
   }

   Future<void> moveSelectedFlashcards(int? destinationFolderId) async {
     final currentState = state.valueOrNull;
     if (currentState == null || currentState.selectedCardIds.isEmpty) return;
     try {
       final dbHelper = await ref.read(databaseHelperProvider.future);
       await dbHelper.moveFlashcards(currentState.selectedCardIds.toList(), destinationFolderId);
       await refreshContent();
     } catch (e) {
       print("Error moving flashcards: $e");
       throw Exception("Failed to move flashcards: $e");
     }
   }

   Future<void> copySelectedFlashcards(int? destinationFolderId) async {
     final currentState = state.valueOrNull;
     if (currentState == null || currentState.selectedCardIds.isEmpty) return;
     try {
       final dbHelper = await ref.read(databaseHelperProvider.future);
       await dbHelper.copyFlashcards(currentState.selectedCardIds.toList(), destinationFolderId);
       if (destinationFolderId == currentState.currentFolder.id) {
          await refreshContent();
       } else {
          // If copied elsewhere, just exit selection mode locally
          state = AsyncData(currentState.copyWith(
              isCardSelectionMode: false,
              selectedCardIds: {}
          ));
       }
     } catch (e) {
       print("Error copying flashcards: $e");
       throw Exception("Failed to copy flashcards: $e");
     }
   }

  // Removed duplicated code block that included ==, hashCode, and all the methods again.
}

// Provider Definition remains the same
final folderDetailProvider = AsyncNotifierProvider.family<FolderDetailNotifier, FolderDetailState, Folder>(
  () => FolderDetailNotifier(),
);