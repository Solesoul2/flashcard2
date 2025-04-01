// lib/widgets/static_flashcard_list_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // To display question

import '../models/flashcard.dart';
import '../utils/helpers.dart'; // For launchUrlHelper

/// A reusable widget that displays a static representation of a flashcard
/// (primarily the question) within a list, suitable for Browse/Folder views.
/// Includes an options menu for editing or deleting the card and selection state.
class StaticFlashcardListTile extends StatelessWidget {
  final Flashcard flashcard;
  final VoidCallback onEdit;   // Callback triggered when 'Edit' is selected
  final VoidCallback onDelete; // Callback triggered when 'Delete' is selected
  final bool isSelected;     // Indicates if the tile is currently selected

  const StaticFlashcardListTile({
    required this.flashcard,
    required this.onEdit,
    required this.onDelete,
    this.isSelected = false, // Default to not selected
    super.key, // Use super key
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      // Apply selection highlight color using ColorScheme if selected, otherwise use default Card color.
      color: isSelected ? colorScheme.primaryContainer.withOpacity(0.3) : null, // Use primaryContainer for M3 selection
      // Use CardTheme properties defined in main.dart (margin, elevation, shape)
      child: Stack( // Use Stack to position the menu button absolutely
        children: [
          // Main content padding (leaving space on right for menu)
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 48.0, 12.0), // Left, Top, Right (for menu), Bottom
            child: MarkdownBody( // Display question using Markdown
              data: flashcard.question,
              selectable: true, // Allow text selection
              onTapLink: (text, href, title) => launchUrlHelper(context, href), // Handle links
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                // Consistent text style
                p: theme.textTheme.bodyLarge?.copyWith(
                  // Ensure text color contrasts with selection background if selected
                  color: isSelected ? colorScheme.onPrimaryContainer : null,
                ),
              ),
            ),
          ),
          // Options menu button positioned at the top-right corner
          Positioned(
            top: 0,
            right: 0,
            child: PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                // Adjust icon color for contrast if selected
                color: isSelected ? colorScheme.onPrimaryContainer : Colors.grey[600],
              ),
              tooltip: 'Card Options',
              // Handle menu item selection by calling the provided callbacks
              onSelected: (value) {
                if (value == 'Edit') {
                  onEdit();
                } else if (value == 'Delete') {
                  onDelete();
                }
              },
              // Define menu items
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'Edit',
                  child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
                ),
                const PopupMenuItem<String>(
                  value: 'Delete',
                  child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
                ),
                // Potential future options could be added here (e.g., Move, Copy)
              ],
            ),
          ),
        ],
      ),
    );
  }
}