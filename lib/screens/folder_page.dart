// lib/screens/folder_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import models, providers, helpers, and screens
import '../models/folder.dart';
import '../providers/root_folders_notifier.dart'; // Import the new notifier
import '../utils/helpers.dart';
import 'folder_detail_page.dart';
import 'flashcard_home_page.dart';

// Change to ConsumerWidget as state is managed by the provider
class FolderPage extends ConsumerWidget {
  const FolderPage({Key? key}) : super(key: key);

  // --- Navigation Methods ---
  // (Context and ref are available in ConsumerWidget build/methods)

  Future<void> _navigateToFolderDetail(BuildContext context, WidgetRef ref, Folder folder) async {
    // Navigate to the detail page
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FolderDetailPage(folder: folder)),
    );
    // Optional: Invalidate provider upon return if needed.
    // In this case, changes within a subfolder don't directly affect this root list view,
    // unless a folder visible here was somehow deleted or renamed from within its detail page (less common).
    // Refreshing via invalidate is safe but potentially unnecessary most of the time.
    // ref.invalidate(rootFoldersNotifierProvider);
  }

  void _navigateToUncategorizedCards(BuildContext context) {
     Navigator.push(context, MaterialPageRoute(builder: (_) => const FlashcardHomePage()));
  }

  // --- Folder Actions (Now interact with the Notifier) ---

  Future<void> _handleAddFolder(BuildContext context, WidgetRef ref) async {
    final String? folderName = await showAddEditFolderDialog(
      context: context,
      dialogTitle: 'Add Root Folder',
    );

    if (folderName != null && folderName.isNotEmpty && context.mounted) {
      try {
        // Call the notifier method to add the folder
        // Use 'ref.read' for actions triggered by user interaction
        await ref.read(rootFoldersNotifierProvider.notifier).addFolder(folderName);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Folder "$folderName" added.')));
          // No need to call refresh manually, provider handles state update
        }
      } catch (e) {
        // Error is already printed in the notifier, show feedback
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error adding folder: ${e.toString().replaceFirst("Exception: ","")}'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _handleRenameFolder(BuildContext context, WidgetRef ref, Folder editingFolder) async {
     final String? newName = await showAddEditFolderDialog(
       context: context,
       editingFolder: editingFolder,
       dialogTitle: 'Rename Folder',
     );

     if (newName != null && newName.isNotEmpty && newName != editingFolder.name && context.mounted) {
        try {
           // Call the notifier method to rename
           await ref.read(rootFoldersNotifierProvider.notifier).renameFolder(editingFolder, newName);

           if (context.mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Folder renamed to "$newName".')));
             // No need to call refresh manually
           }
        } catch (e) {
           if (context.mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error renaming folder: ${e.toString().replaceFirst("Exception: ","")}'), backgroundColor: Colors.red));
           }
        }
     }
  }

  void _showFolderOptions(BuildContext context, WidgetRef ref, Folder folder) {
     // Pass ref down to handlers if needed, or call notifier methods directly
     showModalBottomSheet(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename Folder'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleRenameFolder(context, ref, folder); // Pass ref
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: Colors.red[700]),
                title: Text('Delete Folder', style: TextStyle(color: Colors.red[700])),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmAndDeleteFolder(context, ref, folder); // Pass ref
                },
              ),
            ],
          ),
        ),
     );
  }

   Future<void> _confirmAndDeleteFolder(BuildContext context, WidgetRef ref, Folder folder) async {
      if (folder.id == null) return;

       final confirm = await showConfirmationDialog(
          context: context,
          title: const Text('Confirm Delete'),
          content: Text('Delete folder "${folder.name}"?\n\nWARNING: All subfolders and flashcards inside will be permanently deleted.'),
          confirmActionText: 'Delete',
          isDestructiveAction: true,
       );

       if (confirm == true && context.mounted) {
          try {
            // Call the notifier method to delete
            await ref.read(rootFoldersNotifierProvider.notifier).deleteFolder(folder.id!);

            if (context.mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Folder "${folder.name}" deleted.'))
               );
               // No need to call refresh manually
            }
          } catch (e) {
             if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting folder: ${e.toString().replaceFirst("Exception: ","")}'), backgroundColor: Colors.red)
                );
             }
          }
       }
   }

  // --- UI Build (Uses ConsumerWidget) ---

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the state of the root folders provider
    // Use 'ref.watch' here to rebuild the UI when the state changes
    final asyncRootFolders = ref.watch(rootFoldersNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flashcard Folders'),
        // Theme applied globally
      ),
      drawer: _buildAppDrawer(context), // Drawer logic remains the same
      body: RefreshIndicator(
        // Invalidate the provider to trigger a refetch from the database
        onRefresh: () async => ref.invalidate(rootFoldersNotifierProvider),
        // Use .when to handle the different states of the AsyncValue
        child: asyncRootFolders.when(
          // Loading State UI
          loading: () => const Center(child: CircularProgressIndicator()),
          // Error State UI
          error: (error, stackTrace) {
             // Log the error for debugging purposes
             print("Error loading root folders UI: $error\n$stackTrace");
             // Provide user-friendly error message and retry option
             return Center(
               child: Padding(
                 padding: const EdgeInsets.all(16.0),
                 child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children:[
                      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 48),
                      const SizedBox(height: 16),
                      Text(
                         'Error loading folders.',
                         style: Theme.of(context).textTheme.headlineSmall,
                         textAlign: TextAlign.center,
                       ),
                       const SizedBox(height: 8),
                       Text(
                         'Please check your connection and pull down to refresh.\n(${error.toString().replaceFirst("Exception: ","")})',
                         textAlign: TextAlign.center,
                         style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                       ),
                       const SizedBox(height: 24),
                       ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          // Invalidate provider on retry button press
                          onPressed: () => ref.invalidate(rootFoldersNotifierProvider),
                       )
                    ]
                 ),
               ),
             );
          },
          // Data State UI (list loaded successfully)
          data: (rootFolders) {
            // Handle Empty State
            if (rootFolders.isEmpty) {
              return LayoutBuilder(
                 builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(), // Allow pull-to-refresh even when empty
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                         child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Text(
                              'No folders yet.\nTap the "+" button to add one!',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                            ),
                         )
                      ),
                    ),
                  )
              );
            }

            // Display the list of folders using ListView.builder
            return ListView.builder(
               padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
               itemCount: rootFolders.length,
               itemBuilder: (context, index) {
                  final folder = rootFolders[index];
                  return Card(
                    // Using CardTheme from main.dart
                    child: ListTile(
                      leading: Icon(Icons.folder_outlined, color: Theme.of(context).colorScheme.primary),
                      title: Text(folder.name, style: Theme.of(context).textTheme.titleMedium),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => _navigateToFolderDetail(context, ref, folder), // Pass ref
                      onLongPress: () => _showFolderOptions(context, ref, folder), // Pass ref
                      // Using ListTileTheme from main.dart
                    ),
                  );
               },
            );
          },
        ),
      ),
      // FAB uses FloatingActionButtonTheme from main.dart
      floatingActionButton: FloatingActionButton(
        onPressed: () => _handleAddFolder(context, ref), // Pass ref
        tooltip: 'Add Root Folder',
        child: const Icon(Icons.add),
      ),
    );
  }

  // --- Drawer --- (No changes needed in structure, uses theme)
  Widget _buildAppDrawer(BuildContext context) {
    final theme = Theme.of(context); // Access theme for styling if needed

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: theme.colorScheme.primary), // Use scheme color
            child: Text(
              'Flashcard App',
               // Use appropriate text style from the theme's textTheme for headers
               style: theme.primaryTextTheme.headlineMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: const Text('All Folders'),
            selected: ModalRoute.of(context)?.settings.name == '/', // Example selection logic
            selectedTileColor: theme.listTileTheme.selectedTileColor, // Use theme
            onTap: () {
              Navigator.pop(context); // Close drawer
              // If already on FolderPage, do nothing, else navigate if needed
              if (ModalRoute.of(context)?.settings.name != '/') {
                 Navigator.pushReplacementNamed(context, '/'); // Assuming '/' is the route for FolderPage
              }
            },
          ),
           ListTile(
            leading: const Icon(Icons.style_outlined),
            title: const Text('Uncategorized Cards'),
            selected: ModalRoute.of(context)?.settings.name == '/uncategorized', // Example selection logic
            selectedTileColor: theme.listTileTheme.selectedTileColor, // Use theme
            onTap: () {
              Navigator.pop(context); // Close drawer
              _navigateToUncategorizedCards(context);
            },
          ),
          const Divider(),
          // Add other potential drawer items (Settings, About, etc.) here
          // ListTile(
          //   leading: const Icon(Icons.settings_outlined),
          //   title: const Text('Settings'),
          //   onTap: () {
          //     Navigator.pop(context);
          //     // Navigator.pushNamed(context, '/settings'); // Navigate to settings
          //   },
          // ),
        ],
      ),
    );
  }
}