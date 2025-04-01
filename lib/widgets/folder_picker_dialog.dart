// lib/widgets/folder_picker_dialog.dart
import 'package:flutter/material.dart';

// Import necessary models and services
import '../models/folder.dart';
import '../services/database_helper.dart';

/// A dialog widget that displays a hierarchical list of folders
/// for the user to select a destination folder when moving or copying items.
class FolderPickerDialog extends StatefulWidget {
  final DatabaseHelper dbHelper;

  /// The ID of the folder *from which* items are being moved.
  /// If provided (typically for 'Move' operations), this folder and the
  /// 'Uncategorized' option (if currentFolderId is null) will be disabled as targets.
  /// If null (typically for 'Copy' operations), all folders are valid targets.
  final int? currentFolderId;

  const FolderPickerDialog({
     required this.dbHelper,
     this.currentFolderId, // Optional: Disables selecting this folder in the list
     Key? key,
  }) : super(key: key);

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  // Future to load all folders from the database.
  late Future<List<Folder>> _allFoldersFuture;
  // Cached list of all folders once loaded.
  List<Folder> _allFolders = [];
  // Map to store the hierarchy: parentId -> List<ChildFolders>. Null key represents root.
  final Map<int?, List<Folder>> _folderHierarchy = {};
  // Set to keep track of which folder IDs are currently expanded in the view.
  // Root (null) is expanded by default to show top-level folders.
  final Set<int?> _expandedFolders = {null}; // Initialize with null (root) expanded

  @override
  void initState() {
    super.initState();
    // Fetch all folders when the dialog is initialized.
    _loadAllFolders();
  }

  /// Fetches all folders and builds the hierarchy map.
  void _loadAllFolders() {
    _allFoldersFuture = widget.dbHelper.getAllFolders();
    _allFoldersFuture.then((folders) {
      // Check if the widget is still mounted before updating state.
      if (mounted) {
        setState(() {
          _allFolders = folders;
          // Build the hierarchy map after folders are loaded.
          _buildHierarchy();
        });
      }
    }).catchError((error) {
       // Handle potential errors during folder loading
       print("Error loading folders for picker dialog: $error");
        if (mounted) {
           // Optionally show an error message within the dialog content area
           // For now, the FutureBuilder will show the error.
        }
    });
  }

  /// Organizes the flat list of folders into a parent-child hierarchy map.
  /// Sorts children alphabetically within each level.
  void _buildHierarchy() {
    _folderHierarchy.clear();
    // Ensure the root entry (null parentId) exists even if there are no root folders.
    _folderHierarchy.putIfAbsent(null, () => []);

    for (var folder in _allFolders) {
      // Add each folder to the list associated with its parentId.
      _folderHierarchy.putIfAbsent(folder.parentId, () => []).add(folder);
    }

    // Sort children alphabetically (case-insensitive) within each level.
    _folderHierarchy.forEach((parentId, children) {
      children.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
  }

  /// Recursively builds the list of ListTile widgets representing the folder hierarchy.
  /// [parentId]: The ID of the parent folder whose children are being built (null for root).
  /// [indentLevel]: The current depth in the hierarchy for indentation.
  List<Widget> _buildFolderTiles(int? parentId, int indentLevel) {
    // Get children for the current parentId, default to empty list if none exist.
    final children = _folderHierarchy[parentId] ?? [];
    final List<Widget> tiles = [];

    for (final folder in children) {
       // Determine if this folder should be disabled as a target.
       // It's disabled if we are *moving* (currentFolderId is not null) AND
       // this folder's ID matches the source folder's ID.
       final bool isDisabled = widget.currentFolderId != null && folder.id == widget.currentFolderId;

       // Check if this folder has children (and thus can be expanded).
       final bool canExpand = (_folderHierarchy[folder.id] ?? []).isNotEmpty;
       // Check if this folder is currently marked as expanded.
       final bool isExpanded = _expandedFolders.contains(folder.id);

       tiles.add(
          ListTile(
             enabled: !isDisabled, // Disable tap interaction if needed.
             // Indentation based on hierarchy level using Padding on the leading widget.
             leading: Padding(
                padding: EdgeInsets.only(left: indentLevel * 16.0), // Adjust indent multiplier as needed
                // Show expand/collapse icon button or a fixed-size placeholder for alignment.
                child: SizedBox( // Use SizedBox to control size and alignment
                   width: 40, // Consistent width for leading area
                   child: canExpand
                     ? IconButton(
                         icon: Icon(isExpanded ? Icons.expand_more : Icons.chevron_right, size: 20),
                         padding: EdgeInsets.zero, // Remove default padding
                         constraints: const BoxConstraints(), // Make button compact
                         tooltip: isExpanded ? 'Collapse' : 'Expand',
                         // Toggle expansion state on tap.
                         onPressed: () {
                           setState(() {
                             if (isExpanded) {
                               _expandedFolders.remove(folder.id);
                             } else {
                               _expandedFolders.add(folder.id);
                             }
                           });
                         },
                       )
                     // Use SizedBox with specific width for alignment even if no icon.
                     : const SizedBox(width: 40), // Match width of IconButton area
                ),
             ),
             // Folder name, styled grey if disabled.
             title: Text(
                 folder.name,
                 style: TextStyle(color: isDisabled ? Colors.grey : null)
             ),
             // Return the selected folder ID when tapped (if enabled).
             onTap: isDisabled ? null : () => Navigator.pop(context, folder.id),
             dense: true, // Make tiles more compact vertically.
             visualDensity: VisualDensity.compact, // Further reduce vertical padding.
             // Use theme's selectedTileColor if needed, though selection closes dialog here.
             // selected: false, // Not typically needed here
             // selectedTileColor: Theme.of(context).listTileTheme.selectedTileColor,
          )
       );
       // If the folder is expanded and has children, recursively add its children's tiles.
       if (isExpanded && canExpand) {
          tiles.addAll(_buildFolderTiles(folder.id, indentLevel + 1));
       }
    }
    return tiles;
  }


  @override
  Widget build(BuildContext context) {
    // Determine the dialog title based on whether it's a Move or Copy operation.
    final String dialogTitle = widget.currentFolderId != null ? 'Move to Folder' : 'Copy to Folder';

    return AlertDialog(
      title: Text(dialogTitle),
      // Constrain the content size to prevent the dialog becoming too large.
      content: SizedBox(
        width: double.maxFinite, // Use available width within dialog constraints.
        height: MediaQuery.of(context).size.height * 0.6, // Limit height to 60% of screen.
        // Use FutureBuilder to handle loading the folder list.
        child: FutureBuilder<List<Folder>>(
          future: _allFoldersFuture,
          builder: (context, snapshot) {
            // Show loading indicator while fetching folders.
            if (snapshot.connectionState == ConnectionState.waiting) {
               return const Center(child: CircularProgressIndicator());
            }
            // Show error message if fetching failed.
            if (snapshot.hasError) {
               return Center(child: Text('Error loading folders: ${snapshot.error}'));
            }
            // If data loaded successfully (or is empty)...

            // --- Build the list of selectable items ---
            final List<Widget> selectableItems = [];

            // Add the "Uncategorized" option first.
            // Disable if moving *from* Uncategorized (currentFolderId is null).
            final bool isUncategorizedDisabled = widget.currentFolderId == null;
            selectableItems.add(
               ListTile(
                 enabled: !isUncategorizedDisabled,
                 leading: const Padding(
                    padding: EdgeInsets.only(left: 0), // No indent for root level
                    // Icon representing 'Uncategorized', aligned using SizedBox.
                    child: SizedBox(width: 40, child: Icon(Icons.folder_off_outlined, size: 20, color: Colors.grey)),
                 ),
                 title: Text(
                    'Uncategorized', // Standard name for this option
                    style: TextStyle(
                       color: isUncategorizedDisabled ? Colors.grey : null,
                       fontStyle: FontStyle.italic, // Italicize to distinguish
                    )
                 ),
                 // Return the sentinel value when Uncategorized is picked.
                 onTap: isUncategorizedDisabled
                    ? null
                    : () => Navigator.pop(context, DatabaseHelper.uncategorizedFolderIdSentinel),
                 dense: true,
                 visualDensity: VisualDensity.compact,
               )
            );
            selectableItems.add(const Divider(height: 1)); // Separator

            // Add the hierarchical list of actual folders starting from root (null parentId).
            selectableItems.addAll(_buildFolderTiles(null, 0)); // Start recursion at root (null), level 0

            // Handle case where there are no actual folders created yet.
            if (_allFolders.isEmpty && selectableItems.length <= 2) { // Only Uncategorized + Divider exist
               // Optionally add a message like "No folders created yet."
               // selectableItems.add(const ListTile(title: Text("No folders created yet.")));
            }

            // Use ListView for scrolling if the content overflows the SizedBox height.
            return ListView(
               children: selectableItems,
            );
          },
        ),
      ),
      // Action button to cancel the dialog.
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          // Pop the dialog, returning null to indicate cancellation.
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ],
    );
  }
}