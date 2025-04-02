// lib/screens/study_settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import the study provider to access the state and toggle methods
import '../providers/study_notifier.dart';

// Requires the folderId to know which study session's settings to affect.
// If settings were global, folderId wouldn't be needed here.
// Assuming settings are per-study-session instance.
class StudySettingsPage extends ConsumerWidget {
  final int? folderId; // ID of the folder whose study session settings we are modifying

  const StudySettingsPage({
    required this.folderId,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the specific family instance of the study provider
    final studyStateAsync = ref.watch(studyProvider(folderId));
    // Read the notifier for calling methods
    final studyNotifier = ref.read(studyProvider(folderId).notifier);

    // Get current setting values safely from the state data
    final bool setting1Value = studyStateAsync.valueOrNull?.setting1HideUnmarkedTextWithCheckboxesActive ?? true; // Default to true if state not loaded
    final bool setting2Value = studyStateAsync.valueOrNull?.setting2ShowPreviouslyCheckedItemsActive ?? true; // Default to true if state not loaded
    final bool isLoading = studyStateAsync.isLoading; // Check if state is loading

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Settings'),
        // Uses theme from main.dart
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        children: [
          // Setting 1 Toggle
          SwitchListTile(
            title: const Text('Hide unmarked text lines'),
            subtitle: const Text('Only show text lines (not starting with "*") immediately if they are followed by checklist items. Other text lines appear on reveal.'),
            value: setting1Value,
            // Disable switch while loading state
            onChanged: isLoading ? null : (bool newValue) {
              studyNotifier.toggleSetting1();
            },
            // Apply theme styles implicitly
            // activeColor: Theme.of(context).colorScheme.primary,
          ),

          const Divider(height: 16.0),

          // Setting 2 Toggle
          SwitchListTile(
            title: const Text('Always show checked items'),
            subtitle: const Text('Checklist items (starting with "*") that have been checked will appear immediately, even before revealing the answer.'),
            value: setting2Value,
            // Disable switch while loading state
            onChanged: isLoading ? null : (bool newValue) {
               studyNotifier.toggleSetting2();
            },
            // Apply theme styles implicitly
          ),

          // Optional: Add more settings or information later
        ],
      ),
    );
  }
}