// lib/screens/study_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod

// Import necessary models, services, and widgets
import '../models/flashcard.dart';
import '../models/folder.dart';
import '../widgets/interactive_study_card.dart'; // Needed for ChecklistItem & display constants
import '../providers/study_notifier.dart'; // Import the state provider
import '../utils/helpers.dart'; // Import showConfirmationDialog

/// Provides the study interface using Riverpod for state management.
/// Navigation is handled by buttons ("Skip", "Submit Score") instead of swipes.
class StudyPage extends ConsumerStatefulWidget {
  final Folder folder; // The folder being studied

  const StudyPage({required this.folder, Key? key}) : super(key: key);

  @override
  ConsumerState<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<StudyPage> {

  // Using colors defined in InteractiveStudyCard for consistency
  static const Color _zeroScoreColor = InteractiveStudyCard.zeroScoreColor;
  static const Color _notRatedColor = InteractiveStudyCard.notRatedColor;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Delete confirmation dialog logic
  Future<void> _handleDeleteCard(BuildContext context, Flashcard cardToDelete) async {
    if (cardToDelete.id == null) return;
    final confirm = await showConfirmationDialog(
      context: context,
      title: const Text('Confirm Delete'),
      content: const Text('Delete this flashcard permanently?'),
      confirmActionText: 'Delete',
      isDestructiveAction: true,
    );
    if (confirm == true && context.mounted) {
      try {
        await ref.read(studyProvider(widget.folder.id).notifier).deleteCard(cardToDelete);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flashcard deleted.')));
        }
      } catch (e) {
         if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting card: $e'), backgroundColor: Colors.red));
         }
      }
    }
  }

  // --- Button Action Handlers ---

  void _handleSkip(WidgetRef ref) {
     ref.read(studyProvider(widget.folder.id).notifier).skipCard();
  }

  void _handleSubmitScore(WidgetRef ref) {
     ref.read(studyProvider(widget.folder.id).notifier).rateCard();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final studyStateAsync = ref.watch(studyProvider(widget.folder.id));
    final String appBarTitle = "Study: ${studyStateAsync.valueOrNull?.folderPath.lastOrNull?.name ?? widget.folder.name}";

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: studyStateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center( /* Error UI */
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
                 const SizedBox(height: 16),
                 Text('Error loading study session:', style: theme.textTheme.titleLarge),
                 const SizedBox(height: 8),
                 Text('$err', style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
                 const SizedBox(height: 24),
                 ElevatedButton.icon(
                     icon: const Icon(Icons.refresh),
                     label: const Text('Retry'),
                     onPressed: () => ref.invalidate(studyProvider(widget.folder.id)),
                 )
              ],
            ),
          ),
        ),
        data: (studyData) {
          if (studyData.sessionComplete) { /* Session Complete UI */
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                              Icon(Icons.check_circle_outline, color: theme.colorScheme.primary, size: 64),
                              const SizedBox(height: 24),
                              Text(
                                  'Study session complete!',
                                  style: theme.textTheme.headlineSmall,
                                  textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                  'You have reviewed all due cards for this session.',
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              ElevatedButton.icon(
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('Go Back'),
                                  onPressed: () {
                                      if (Navigator.canPop(context)) {
                                          Navigator.pop(context);
                                      }
                                  },
                              )
                          ],
                      )
                  )
              );
          }
          if (studyData.cards.isEmpty) { /* No Cards UI */
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                 child: Text(
                  'This folder has no flashcards to study.\nAdd some cards first, or go back.',
                   textAlign: TextAlign.center,
                   style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                 ),
              )
            );
          }

          final int currentIndex = studyData.currentPageIndex;
          if (currentIndex < 0 || currentIndex >= studyData.cards.length) { /* Invalid Index UI */
             print("Error: Invalid current index ($currentIndex) despite session not being complete.");
             return Center( /* ... Error UI ... */ );
          }

          // --- Get Data from State ---
          final Flashcard currentCard = studyData.cards[currentIndex];
          final bool isCurrentAnswerShown = studyData.isCurrentAnswerShown;
          final List<ChecklistItem> currentChecklistItems = (currentIndex < studyData.checklistItemsState.length)
                                                              ? studyData.checklistItemsState[currentIndex] : [];
          final String currentAnswerMarkdown = (currentIndex < studyData.answerMarkdownState.length)
                                                ? studyData.answerMarkdownState[currentIndex] : "";
          // Use live color from state, converting old grey reference to new grey if necessary
          final Color liveRatingColor = studyData.currentCardRatingColor == const Color(0xFFbdbdbd) /* old grey */
                                         ? _notRatedColor // use new grey
                                         : studyData.currentCardRatingColor;
          final int? lastQuality = studyData.currentCardLastRatingQuality;
          final bool canPressSubmit = isCurrentAnswerShown;

          // --- Determine Final Card Color (for Top Bar & Reveal Button) ---
          Color finalCardColor;
          bool lastRatingWasZero = lastQuality != null && lastQuality < 3;
          if (liveRatingColor == _notRatedColor && lastRatingWasZero) {
              finalCardColor = _zeroScoreColor; // Use purple/magenta
          } else if (liveRatingColor == _notRatedColor && lastQuality == null) {
              finalCardColor = _notRatedColor; // Use bluish-grey
          } else {
              finalCardColor = liveRatingColor; // Use live gradient color
          }

          // --- Determine Submit Button Colors ---
          Color submitButtonBackgroundColor;
          if (!canPressSubmit) {
             submitButtonBackgroundColor = theme.colorScheme.onSurface.withOpacity(0.12);
          } else {
              // Submit button color *only* changes based on live interaction OR historical override when grey
              if (liveRatingColor == _notRatedColor && lastRatingWasZero) {
                 submitButtonBackgroundColor = _zeroScoreColor;
              } else if (liveRatingColor == _notRatedColor && lastQuality == null) {
                 submitButtonBackgroundColor = _notRatedColor;
              } else {
                 submitButtonBackgroundColor = liveRatingColor;
              }
          }
          final bool useWhiteTextOnSubmit = submitButtonBackgroundColor.computeLuminance() < 0.5;
          final Color submitButtonForegroundColor = !canPressSubmit
                ? theme.colorScheme.onSurface.withOpacity(0.38)
                : useWhiteTextOnSubmit ? Colors.white : Colors.black87;


          // --- Build Reveal/Hide Button ---
          Widget revealHideButton;
          if (isCurrentAnswerShown) {
            // Use a TextButton with an Icon when answer is shown
            revealHideButton = TextButton(
              onPressed: () => ref.read(studyProvider(widget.folder.id).notifier).toggleAnswerVisibility(),
              style: TextButton.styleFrom(
                foregroundColor: _notRatedColor, // Use the grey color for the icon's color
                minimumSize: const Size(double.infinity, 48), // Match height
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                shape: RoundedRectangleBorder( // Match ElevatedButton shape
                   side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3)), // Subtle border
                   borderRadius: BorderRadius.circular(8.0)
                )
              ),
              child: const Icon(Icons.keyboard_arrow_up),
            );
          } else {
            // Use ElevatedButton with Text when answer is hidden
            // *** USE finalCardColor for background ***
            final bool useWhiteTextOnReveal = finalCardColor.computeLuminance() < 0.5;
            final Color revealFgColor = useWhiteTextOnReveal ? Colors.white : Colors.black87;
            revealHideButton = ElevatedButton(
              onPressed: () => ref.read(studyProvider(widget.folder.id).notifier).toggleAnswerVisibility(),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  backgroundColor: finalCardColor, // Use the final calculated color
                  foregroundColor: revealFgColor, // Text color based on final background
                  textStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)
              ),
              child: const Text('REVEAL ANSWER'),
            );
          }
          // --- End Reveal/Hide Button ---


          return Column(
            children: [
              Expanded( // InteractiveStudyCard
                child: InteractiveStudyCard(
                  key: ValueKey('study_card_${currentCard.id}_${studyData.cards.length}_$currentIndex'),
                  flashcard: currentCard,
                  folder: widget.folder,
                  folderPath: studyData.folderPath,
                  currentCardIndex: currentIndex + 1,
                  totalCardCount: studyData.cards.length,
                  isAnswerShown: isCurrentAnswerShown,
                  checklistItems: currentChecklistItems,
                  answerMarkdownContent: currentAnswerMarkdown,
                  lastRatingQuality: lastQuality,
                  onChecklistChanged: (itemIndex, isChecked) => ref.read(studyProvider(widget.folder.id).notifier).handleChecklistChanged(itemIndex, isChecked),
                  onRatingColorCalculated: (id, color) {
                        ref.read(studyProvider(widget.folder.id).notifier).updateRatingColor(id, color);
                  },
                  onDelete: () => _handleDeleteCard(context, currentCard),
                ),
              ),
              SafeArea( // Footer Buttons
                top: false, left: false, right: false,
                child: Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                 child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Use the dynamic revealHideButton
                      revealHideButton,
                      const SizedBox(height: 8),
                      // Skip/Submit Row (visible only when answer is shown)
                      Visibility(
                        visible: isCurrentAnswerShown,
                        maintainState: true, maintainAnimation: true, maintainSize: true,
                        child: Row(
                          children: [
                            Expanded( // Skip Button
                              child: OutlinedButton(
                                onPressed: () => _handleSkip(ref),
                                style: OutlinedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 10.0) ),
                                child: const Text('SKIP'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded( // Submit Score Button
                              child: ElevatedButton(
                                onPressed: canPressSubmit ? () => _handleSubmitScore(ref) : null,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                                  backgroundColor: submitButtonBackgroundColor,
                                  foregroundColor: submitButtonForegroundColor,
                                ),
                                child: const Text('SUBMIT SCORE'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Placeholder height if Skip/Submit are hidden
                      if (!isCurrentAnswerShown) const SizedBox(height: 48),
                    ],
                 ),
               ),
              ), // End SafeArea
            ],
          );
        },
      ), // End body: studyStateAsync.when(...)
    ); // End Scaffold
  }
}