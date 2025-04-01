// lib/providers/root_folders_notifier.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../providers/service_providers.dart'; // Access DatabaseHelper provider

// Manually defined AsyncNotifier
class RootFoldersNotifier extends AsyncNotifier<List<Folder>> {

  // Fetches the initial list of root folders
  @override
  Future<List<Folder>> build() async {
    // 'ref' is automatically available in AsyncNotifier
    final dbHelper = await ref.watch(databaseHelperProvider.future);
    return dbHelper.getFolders(parentId: null); // Fetch root folders
  }

  // Action to add a new root folder
  Future<void> addFolder(String name) async {
    if (name.trim().isEmpty) return;

    // Use ref.read inside methods for one-off reads
    final dbHelper = await ref.read(databaseHelperProvider.future);
    final newFolder = Folder(name: name.trim(), parentId: null);

    // Set state to loading optimistically while saving
    state = const AsyncLoading();

    try {
      await dbHelper.insertFolder(newFolder);
      // Invalidate provider to refetch the list from DB after successful insert
      ref.invalidateSelf();
      // Ensure the state updates by awaiting the future that resolves after invalidation
      await future;
    } catch (e) {
      print("Error adding root folder: $e");
      // If an error occurs, set the state back or let invalidateSelf handle refetch
      // Setting state to AsyncError might be better if refetch is not desired on error
      state = AsyncError(e, StackTrace.current);
      // Rethrow to allow UI to potentially display the error
      throw Exception('Failed to add folder: $e');
    }
  }

  // Action to rename a folder
  Future<void> renameFolder(Folder folderToRename, String newName) async {
     if (folderToRename.id == null || newName.trim().isEmpty || newName.trim() == folderToRename.name) {
       return;
     }
     final dbHelper = await ref.read(databaseHelperProvider.future);

     state = const AsyncLoading(); // Show loading during update

     try {
        await dbHelper.updateFolder(folderToRename.copyWith(name: newName.trim()));
        ref.invalidateSelf(); // Refetch to update the list
        await future; // Wait for refetch
     } catch (e) {
        print("Error renaming folder: $e");
        state = AsyncError(e, StackTrace.current);
        throw Exception('Failed to rename folder: $e');
     }
   }

   // Action to delete a folder
   Future<void> deleteFolder(int folderId) async {
     final dbHelper = await ref.read(databaseHelperProvider.future);

     state = const AsyncLoading(); // Show loading during delete

     try {
       await dbHelper.deleteFolder(folderId);
       ref.invalidateSelf(); // Refetch to update the list
       await future; // Wait for refetch
     } catch (e) {
       print("Error deleting folder: $e");
       state = AsyncError(e, StackTrace.current);
       throw Exception('Failed to delete folder: $e');
     }
   }
}

// Manually defined AsyncNotifierProvider
final rootFoldersNotifierProvider =
    AsyncNotifierProvider<RootFoldersNotifier, List<Folder>>(
  () => RootFoldersNotifier(),
);