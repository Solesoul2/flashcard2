// lib/screens/csv_import_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import necessary models, providers
import '../models/folder.dart';
import '../providers/csv_import_notifier.dart'; // Import the new provider and state class

// Change to ConsumerWidget as state is managed by the provider
class CsvImportPage extends ConsumerWidget {
  // The folder into which cards will be imported
  final Folder folder;

  const CsvImportPage({required this.folder, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the state from the provider, passing the folder as the family argument.
    // ref.watch ensures the widget rebuilds when the CsvImportState changes.
    final CsvImportState importState = ref.watch(csvImportProvider(folder));

    // Get the notifier to call its methods (like selectCsvFile, importCsv).
    // Use ref.read here because we are calling methods in response to user actions,
    // not rebuilding the UI based on the notifier instance itself.
    final CsvImportNotifier notifier = ref.read(csvImportProvider(folder).notifier);

    return Scaffold(
      appBar: AppBar(
        // Title uses the folder passed during navigation
        title: Text('Import to "${folder.name}"'),
        // Uses AppBarTheme from main.dart
      ),
      body: Padding(
        // Consistent padding around the body content
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Make buttons fill width
          children: [
            // --- Select File Button ---
            ElevatedButton.icon(
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Select CSV File'),
              // Disable the button if an import is currently in progress
              onPressed: importState.isImporting ? null : notifier.selectCsvFile,
              // Uses ElevatedButtonTheme from main.dart
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
            const SizedBox(height: 16), // Spacing between buttons

            // --- Start Import Button ---
            ElevatedButton.icon(
              // Show a progress indicator inside the button when importing
              icon: importState.isImporting
                  ? SizedBox(
                      width: 20, // Constrain size of the indicator
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        // Use foreground color from theme for consistency, or specify white
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.download_done_outlined), // Normal icon
              label: Text(importState.isImporting ? 'Importing...' : 'Start Import'),
              // Disable button if no file content has been selected OR if an import is already in progress
              onPressed: (importState.csvFileContent.isEmpty || importState.isImporting)
                  ? null
                  : notifier.importCsv,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                // Use disabledColor/onSurface.withOpacity from theme automatically when onPressed is null
                // Or, explicitly define disabled styles if needed:
                // disabledBackgroundColor: Colors.grey[300],
                // disabledForegroundColor: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24), // Spacing below buttons

            // --- Status Message Area ---
            // Conditionally display the status message container if the message is not empty
            if (importState.statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                decoration: BoxDecoration(
                  // Optional: Add a subtle background for emphasis
                  // color: importState.statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  importState.statusMessage,
                  // Use the status color defined in the CsvImportState
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: importState.statusColor),
                  textAlign: TextAlign.center,
                ),
              ),

            // Use Spacer to push the help text to the bottom of the column
            const Spacer(),

            // --- Help Text ---
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0), // Padding at the very bottom
              child: Text(
                // Guidance text about the expected CSV format
                'Expected CSV format (UTF-8):\nColumn 1: Question\nColumn 2: Answer\n(An optional header row "Question,Answer" will be skipped)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}