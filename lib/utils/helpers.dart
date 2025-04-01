// lib/utils/helpers.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/folder.dart'; // Needed for showAddEditFolderDialog

/// A collection of utility functions for the application.

/// Attempts to launch the given [urlString] in an external application.
Future<void> launchUrlHelper(BuildContext context, String? urlString) async {
  // ... (existing launchUrlHelper implementation remains the same) ...
  if (urlString == null || urlString.trim().isEmpty) {
    print('Attempted to launch a null or empty URL string.');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open link: URL is missing or invalid.')),
      );
    }
    return;
  }

  Uri? uri;
  try {
    uri = Uri.parse(urlString.trim());
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    print('Error launching URL $urlString: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $urlString')),
      );
    }
  }
}


/// Shows a confirmation dialog to the user.
/// Returns `true` if the user confirms, `false` otherwise.
Future<bool> showConfirmationDialog({
  required BuildContext context,
  Widget title = const Text('Confirm Action'),
  required Widget content,
  String confirmActionText = 'Confirm',
  bool isDestructiveAction = true,
}) async {
  // ... (existing showConfirmationDialog implementation remains the same) ...
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: title,
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            confirmActionText,
            style: TextStyle(color: isDestructiveAction ? Colors.red[700] : null),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}


/// Shows a dialog to add or edit a folder name.
///
/// Returns the validated folder name as a String if the user saves,
/// or `null` if the user cancels.
///
/// - [context]: The BuildContext required to show the dialog.
/// - [editingFolder]: The optional [Folder] being edited (provides initial name).
/// - [dialogTitle]: The title for the dialog (e.g., 'Add Folder', 'Rename Folder').
Future<String?> showAddEditFolderDialog({
  required BuildContext context,
  Folder? editingFolder, // Pass the folder being edited, if any
  required String dialogTitle, // Explicitly require title (e.g., Add/Rename)
}) async {
  final folderController = TextEditingController(text: editingFolder?.name ?? '');
  final formKey = GlobalKey<FormState>(); // For validation

  // Show the dialog and wait for the result (the entered name or null)
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogTitle),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: folderController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'Enter folder name...',
          ),
          validator: (value) { // Basic validation
            if (value == null || value.trim().isEmpty) {
              return 'Folder name cannot be empty.';
            }
            return null; // Valid
          },
          // Allow submitting via keyboard action
          onFieldSubmitted: (_) {
            if (formKey.currentState!.validate()) {
              // Pop dialog and return the trimmed name
              Navigator.pop(dialogContext, folderController.text.trim());
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, null), // Return null on cancel
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              // Pop dialog and return the trimmed name
              Navigator.pop(dialogContext, folderController.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );

  // The result will be the trimmed name string or null
  return result;
}

// Add other common helper functions here in the future.