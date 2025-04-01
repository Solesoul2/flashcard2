// lib/screens/folder_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import models, providers, widgets, helpers, screens
import '../models/folder.dart';
import '../models/flashcard.dart';
import '../providers/folder_detail_notifier.dart';
import '../services/database_helper.dart'; // Still needed for sentinel value
import '../providers/service_providers.dart'; // Import service providers
import '../widgets/folder_picker_dialog.dart';
import '../widgets/static_flashcard_list_tile.dart';
import '../utils/helpers.dart';
import 'flashcard_edit_page.dart';
import 'csv_import_page.dart';
import 'study_page.dart';
import 'browse_page.dart'; // Import Browse Page

// ConsumerWidget for Riverpod integration
class FolderDetailPage extends ConsumerWidget {
  final Folder folder;

  const FolderDetailPage({required this.folder, Key? key}) : super(key: key);

  // --- Navigation Methods ---

  Future<void> _navigateToEditFlashcard(BuildContext context, WidgetRef ref, {Flashcard? flashcard}) async {
     final result = await Navigator.push(
       context,
       MaterialPageRoute(
          builder: (_) => FlashcardEditPage(folder: folder, flashcard: flashcard)
       ),
     );
     // Refresh content if an edit occurred
     if (result == true) {
         await ref.read(folderDetailProvider(folder).notifier).refreshContent();
     }
  }

  Future<void> _navigateToStudy(BuildContext context, WidgetRef ref) async {
     // Check if folder has an ID (cannot study uncategorized directly)
     if (folder.id == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot study uncategorized cards directly.')));
        return;
     }
     // Check if there are cards to study in the current state
     final state = ref.read(folderDetailProvider(folder)).valueOrNull;
     if (state == null || state.flashcards.isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This folder has no flashcards to study.')));
         return;
     }
     // Navigate to Study Page
     await Navigator.push(
       context,
       MaterialPageRoute(builder: (_) => StudyPage(folder: folder)),
     );
     // Refresh content when returning from study page (in case cards were deleted)
     await ref.read(folderDetailProvider(folder).notifier).refreshContent();
   }

   // Navigate to Browse Page
   Future<void> _navigateToBrowse(BuildContext context, WidgetRef ref) async {
     // Check if there are cards to browse
     final state = ref.read(folderDetailProvider(folder)).valueOrNull;
      if (state == null || state.flashcards.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This folder has no flashcards to browse.')));
          return;
      }
      // Navigate to Browse Page
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BrowsePage(folder: folder)),
      );
      // Optional: Refresh content when returning if edits/deletes were possible in BrowsePage
      // await ref.read(folderDetailProvider(folder).notifier).refreshContent();
   }


   Future<void> _navigateToSubfolderDetail(BuildContext context, WidgetRef ref, Folder subfolder) async {
      await Navigator.push(
         context,
         MaterialPageRoute(builder: (_) => FolderDetailPage(folder: subfolder)),
      );
      // Refresh current folder content when returning from subfolder
      await ref.read(folderDetailProvider(folder).notifier).refreshContent();
   }

   Future<void> _navigateToCsvImport(BuildContext context, WidgetRef ref) async {
      await Navigator.push(context, MaterialPageRoute(
         builder: (_) => CsvImportPage(folder: folder)
      ));
      // Refresh content after potential import
      await ref.read(folderDetailProvider(folder).notifier).refreshContent();
   }

   // --- Action Menus and Dialogs ---

   void _showAddOptions(BuildContext context, WidgetRef ref) {
    // Allow adding subfolders only if the current folder is not 'Uncategorized'
    bool allowAddSubfolder = folder.id != null;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined), title: const Text('Add Flashcard'),
              onTap: () { Navigator.pop(sheetContext); _navigateToEditFlashcard(context, ref); },
            ),
            if (allowAddSubfolder)
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined), title: const Text('Add Subfolder'),
                onTap: () { Navigator.pop(sheetContext); _handleAddSubfolder(context, ref); },
              ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined), title: const Text('Import from CSV'),
              onTap: () { Navigator.pop(sheetContext); _navigateToCsvImport(context, ref); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAddSubfolder(BuildContext context, WidgetRef ref) async {
    if (folder.id == null) return; // Cannot add subfolder to 'Uncategorized'
    final String? folderName = await showAddEditFolderDialog(
      context: context,
      dialogTitle: 'Add Subfolder',
    );
    if (folderName != null && folderName.isNotEmpty) {
      try {
        await ref.read(folderDetailProvider(folder).notifier).addSubfolder(folderName);
         if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Subfolder "$folderName" added.')));
          }
      } catch (e) {
         if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error adding subfolder: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red));
          }
      }
    }
  }

   Future<void> _handleRenameFolder(BuildContext context, WidgetRef ref, Folder folderToRename) async {
     final String? newName = await showAddEditFolderDialog(
       context: context,
       editingFolder: folderToRename,
       dialogTitle: folderToRename.id == folder.id ? 'Rename Folder' : 'Rename Subfolder',
     );
     if (newName != null && newName.isNotEmpty && newName != folderToRename.name) {
        try {
           // Use the notifier of the *parent* folder to rename the item
           await ref.read(folderDetailProvider(folder).notifier).renameFolder(folderToRename, newName);
            if (context.mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Folder renamed to "$newName".')));
            }
        } catch (e) {
            if (context.mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error renaming folder: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red));
            }
        }
     }
  }

   void _showSubfolderOptions(BuildContext context, WidgetRef ref, Folder subfolder) {
      showModalBottomSheet(
         context: context,
         builder: (sheetContext) => SafeArea(
           child: Wrap(
             children: [
               ListTile(
                 leading: const Icon(Icons.edit_outlined), title: const Text('Rename Subfolder'),
                 onTap: () { Navigator.pop(sheetContext); _handleRenameFolder(context, ref, subfolder); },
               ),
               ListTile(
                 leading: Icon(Icons.delete_forever_outlined, color: Colors.red[700]),
                 title: Text('Delete Subfolder', style: TextStyle(color: Colors.red[700])),
                 onTap: () { Navigator.pop(sheetContext); _confirmAndDeleteSubfolder(context, ref, subfolder); },
               ),
             ],
           ),
         ),
      );
   }

   Future<void> _confirmAndDeleteSubfolder(BuildContext context, WidgetRef ref, Folder subfolder) async {
     if (subfolder.id == null) return;
     final confirm = await showConfirmationDialog(
         context: context,
         title: const Text('Confirm Delete'),
         content: Text('Delete "${subfolder.name}"?\n\nAll content inside (subfolders and flashcards) will also be deleted permanently.'),
         confirmActionText: 'Delete',
         isDestructiveAction: true,
      );
      if (confirm == true) {
         try {
            // Use the notifier of the *parent* folder (current context) to delete the subfolder
            await ref.read(folderDetailProvider(folder).notifier).deleteSubfolder(subfolder.id!);
             if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Subfolder "${subfolder.name}" deleted')));
             }
         } catch (e) {
             if (context.mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting subfolder: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red));
            }
         }
      }
   }

  Future<void> _handleDeleteFlashcard(BuildContext context, WidgetRef ref, Flashcard flashcard) async {
    if (flashcard.id == null) return;
    final bool confirmed = await showConfirmationDialog(
      context: context,
      title: const Text('Confirm Delete'),
      content: const Text('Delete this flashcard?'),
      confirmActionText: 'Delete',
      isDestructiveAction: true,
    );
    if (confirmed == true) {
      try {
        await ref.read(folderDetailProvider(folder).notifier).deleteFlashcard(flashcard.id!);
         if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Flashcard deleted.'), duration: Duration(seconds: 2)));
         }
      } catch (e) {
         if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting flashcard: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red));
          }
      }
    }
  }

  Future<void> _showMoveCardDialog(BuildContext context, WidgetRef ref) async {
     final stateValue = ref.read(folderDetailProvider(folder)).valueOrNull;
     if (stateValue == null || stateValue.selectedCardIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No cards selected to move.')));
        return;
     }
     final dbHelper = await ref.read(databaseHelperProvider.future);
     if (!context.mounted) return;

     final destinationFolderId = await showDialog<int?>(
        context: context,
        builder: (_) => FolderPickerDialog(dbHelper: dbHelper, currentFolderId: folder.id),
     );

     if (destinationFolderId != null) {
         final targetId = destinationFolderId == DatabaseHelper.uncategorizedFolderIdSentinel ? null : destinationFolderId;
         if (targetId == folder.id) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot move cards to the same folder.')));
             return;
         }
         try {
            await ref.read(folderDetailProvider(folder).notifier).moveSelectedFlashcards(targetId);
             if (context.mounted) {
               final count = stateValue.selectedCardIds.length;
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved $count card(s).')));
             }
         } catch (e) {
             if (context.mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error moving cards: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red));
            }
         }
     }
  }

  Future<void> _showCopyCardDialog(BuildContext context, WidgetRef ref) async {
     final stateValue = ref.read(folderDetailProvider(folder)).valueOrNull;
     if (stateValue == null || stateValue.selectedCardIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No cards selected to copy.')));
        return;
     }
     final dbHelper = await ref.read(databaseHelperProvider.future);
     if (!context.mounted) return;

     final destinationFolderId = await showDialog<int?>(
        context: context,
        builder: (_) => FolderPickerDialog(dbHelper: dbHelper), // No currentFolderId needed for copy
     );

     if (destinationFolderId != null) {
         final targetId = destinationFolderId == DatabaseHelper.uncategorizedFolderIdSentinel ? null : destinationFolderId;
         try {
            await ref.read(folderDetailProvider(folder).notifier).copySelectedFlashcards(targetId);
            if (context.mounted) {
               final count = stateValue.selectedCardIds.length;
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $count card(s).')));
             }
             // Refresh only if copying to the *same* folder
             if (targetId == stateValue.currentFolder.id) {
                 await ref.read(folderDetailProvider(folder).notifier).refreshContent();
             }

         } catch (e) {
            if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error copying cards: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red));
            }
         }
     }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(folderDetailProvider(folder));
    final bool isSelectionMode = asyncState.valueOrNull?.isCardSelectionMode ?? false;
    final int selectedCount = asyncState.valueOrNull?.selectedCardIds.length ?? 0;
    final String currentFolderName = asyncState.valueOrNull?.currentFolder.name ?? folder.name;
    List<Widget> appBarActions = _buildAppBarActions(context, ref, asyncState.valueOrNull);

    return Scaffold(
      appBar: AppBar(
        title: Text(isSelectionMode ? '$selectedCount Selected' : currentFolderName),
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel Selection',
                onPressed: () => ref.read(folderDetailProvider(folder).notifier).cancelCardSelection()
              )
            : null,
        actions: appBarActions,
        backgroundColor: isSelectionMode ? Theme.of(context).colorScheme.secondaryContainer : null,
        foregroundColor: isSelectionMode ? Theme.of(context).colorScheme.onSecondaryContainer : null,
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) {
           print("Error in FolderDetailPage build: $err\n$stack");
           return Center(
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                       Text('Error loading folder contents:\n${err.toString().replaceFirst("Exception: ", "")}',
                           style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
                       const SizedBox(height: 16),
                       ElevatedButton.icon(
                           icon: const Icon(Icons.refresh),
                           label: const Text('Retry'),
                           onPressed: () => ref.invalidate(folderDetailProvider(folder)),
                       )
                   ]
               ),
             ),
           );
        },
        data: (stateData) => RefreshIndicator(
          onRefresh: () => ref.read(folderDetailProvider(folder).notifier).refreshContent(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              // Subfolders Section
              if (!stateData.isCardSelectionMode && stateData.currentFolder.id != null)
                 _buildSubfoldersSection(context, ref, stateData.subfolders),

              // Divider
              if (!stateData.isCardSelectionMode && stateData.currentFolder.id != null && stateData.subfolders.isNotEmpty)
                 const Divider(height: 1.0, thickness: 1),

              // Flashcards Section
               _buildFlashcardsSection(context, ref, stateData),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Build Methods ---

  List<Widget> _buildAppBarActions(BuildContext context, WidgetRef ref, FolderDetailState? stateData) {
    final bool isSelectionMode = stateData?.isCardSelectionMode ?? false;
    final int selectedCount = stateData?.selectedCardIds.length ?? 0;
    final bool hasFlashcards = stateData?.flashcards.isNotEmpty ?? false;
    final bool isRealFolder = stateData?.currentFolder.id != null;

    if (isSelectionMode) {
       // Actions for Card Selection Mode
       if (selectedCount == 0) return [];
       return [
         IconButton( icon: const Icon(Icons.copy_all_outlined), tooltip: 'Copy Selected ($selectedCount)',
           onPressed: () => _showCopyCardDialog(context, ref), ),
         IconButton( icon: const Icon(Icons.drive_file_move_outlined), tooltip: 'Move Selected ($selectedCount)',
           onPressed: () => _showMoveCardDialog(context, ref), ),
       ];
    } else {
       // Actions for Normal Mode
       return [
          // Browse Button
          if (hasFlashcards)
            IconButton( icon: const Icon(Icons.view_carousel_outlined), tooltip: 'Browse Cards',
              onPressed: () => _navigateToBrowse(context, ref), ),
          // Study Button
          if (isRealFolder && hasFlashcards)
             IconButton( icon: const Icon(Icons.school_outlined), tooltip: 'Study This Folder',
               onPressed: () => _navigateToStudy(context, ref), ),
          // Rename Button
          if (isRealFolder)
             IconButton( icon: const Icon(Icons.edit_outlined), tooltip: 'Rename Folder',
                 onPressed: () => _handleRenameFolder(context, ref, stateData?.currentFolder ?? folder) ),
          // Add Button
          IconButton( icon: const Icon(Icons.add_circle_outline), tooltip: 'Add Content',
              onPressed: () => _showAddOptions(context, ref) ),
       ];
    }
  }

  Widget _buildSubfoldersSection(BuildContext context, WidgetRef ref, List<Folder> subfolders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Padding(
           padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
           child: Text('Subfolders', style: Theme.of(context).textTheme.titleMedium),
         ),
         if (subfolders.isEmpty)
            const ListTile( title: Text('No subfolders.', style: TextStyle(color: Colors.grey)), dense: true )
         else
            ListView.builder(
               shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
               itemCount: subfolders.length,
               itemBuilder: (context, index) {
                  final subfolder = subfolders[index];
                  return ListTile(
                     leading: Icon(Icons.folder_outlined, color: Theme.of(context).colorScheme.secondary),
                     title: Text(subfolder.name),
                     trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                     onTap: () => _navigateToSubfolderDetail(context, ref, subfolder),
                     onLongPress: () => _showSubfolderOptions(context, ref, subfolder),
                     dense: true, visualDensity: VisualDensity.compact,
                  );
               },
             ),
      ],
    );
  }

  Widget _buildFlashcardsSection(BuildContext context, WidgetRef ref, FolderDetailState stateData) {
    final flashcards = stateData.flashcards;
    final isSelectionMode = stateData.isCardSelectionMode;
    final selectedIds = stateData.selectedCardIds;

    return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
          Padding(
            // *** CORRECTION HERE: Removed 'const' ***
            padding: EdgeInsets.fromLTRB(
                16.0,
                (stateData.currentFolder.id != null && stateData.subfolders.isNotEmpty ? 8.0 : 16.0), // Conditional top padding
                16.0,
                8.0),
            child: Text('Flashcards', style: Theme.of(context).textTheme.titleMedium),
          ),
          if (flashcards.isEmpty)
             const ListTile( title: Text('No flashcards in this folder.', style: TextStyle(color: Colors.grey)), dense: true, )
          else
             ListView.builder(
               shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
               itemCount: flashcards.length,
               padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
               itemBuilder: (context, index) {
                  final flashcard = flashcards[index];
                  final cardId = flashcard.id;
                  final bool isSelected = cardId != null && selectedIds.contains(cardId);

                  return GestureDetector(
                      onLongPress: cardId == null ? null : () {
                           ref.read(folderDetailProvider(folder).notifier).enterCardSelectionMode(cardId);
                      },
                      onTap: cardId == null ? null : () {
                          if (isSelectionMode) {
                             ref.read(folderDetailProvider(folder).notifier).toggleCardSelection(cardId);
                          }
                       },
                      child: StaticFlashcardListTile(
                         flashcard: flashcard,
                         isSelected: isSelected,
                         onEdit: () => _navigateToEditFlashcard(context, ref, flashcard: flashcard),
                         onDelete: () => _handleDeleteFlashcard(context, ref, flashcard),
                       ),
                  );
               },
             ),
       ],
    );
  }
}