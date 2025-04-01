// lib/screens/study_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod

// Import necessary models, services, and widgets
import '../models/flashcard.dart';
import '../models/folder.dart';
// Import the new state structures from the notifier
import '../providers/study_notifier.dart';
// Import InteractiveStudyCard and ChecklistItem (though ChecklistItem might not be directly needed here)
import '../widgets/interactive_study_card.dart';
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

  // Color constants remain the same
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

  // Delete confirmation dialog logic (remains the same)
  Future<void> _handleDeleteCard(BuildContext context, Flashcard cardToDelete) async {
    if (cardToDelete.id == null) return;
    final confirm = await showConfirmationDialog( context: context, title: const Text('Confirm Delete'), content: const Text('Delete this flashcard permanently?'), confirmActionText: 'Delete', isDestructiveAction: true );
    if (confirm == true && context.mounted) {
      try {
        await ref.read(studyProvider(widget.folder.id).notifier).deleteCard(cardToDelete);
        if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flashcard deleted.'))); }
      } catch (e) { if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting card: $e'), backgroundColor: Colors.red)); } }
    }
  }

  // Button Action Handlers (remain the same)
  void _handleSkip(WidgetRef ref) { ref.read(studyProvider(widget.folder.id).notifier).skipCard(); }
  void _handleSubmitScore(WidgetRef ref) { ref.read(studyProvider(widget.folder.id).notifier).rateCard(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final studyStateAsync = ref.watch(studyProvider(widget.folder.id));
    final String appBarTitle = "Study: ${studyStateAsync.valueOrNull?.folderPath.lastOrNull?.name ?? widget.folder.name}";

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: studyStateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center( /* Error UI remains the same */
          child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48), const SizedBox(height: 16), Text('Error loading study session:', style: theme.textTheme.titleLarge), const SizedBox(height: 8), Text('$err', style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center), const SizedBox(height: 24), ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: () => ref.invalidate(studyProvider(widget.folder.id)), ) ], ), ),
        ),
        data: (studyData) {
          if (studyData.sessionComplete) { /* Session Complete UI remains the same */
              return Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.check_circle_outline, color: theme.colorScheme.primary, size: 64), const SizedBox(height: 24), Text( 'Study session complete!', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center, ), const SizedBox(height: 16), Text( 'You have reviewed all due cards for this session.', style: theme.textTheme.bodyLarge, textAlign: TextAlign.center, ), const SizedBox(height: 32), ElevatedButton.icon( icon: const Icon(Icons.arrow_back), label: const Text('Go Back'), onPressed: () { if (Navigator.canPop(context)) { Navigator.pop(context); } }, ) ], ) ) );
          }
          if (studyData.cards.isEmpty) { /* No Cards UI remains the same */
            return Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Text( 'This folder has no flashcards to study.\nAdd some cards first, or go back.', textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]), ), ) );
          }

          final int currentIndex = studyData.currentPageIndex;
          if (currentIndex < 0 || currentIndex >= studyData.cards.length) { /* Invalid Index UI remains the same */
             print("Error: Invalid current index ($currentIndex) despite session not being complete.");
             return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48), const SizedBox(height: 16), Text('Internal Error: Invalid card index.', style: theme.textTheme.titleLarge), const SizedBox(height: 24), ElevatedButton.icon( icon: const Icon(Icons.arrow_back), label: const Text('Go Back'), onPressed: () { if (Navigator.canPop(context)) { Navigator.pop(context); } }, ) ], ), ), );
          }

          // --- Get Data from State ---
          final Flashcard currentCard = studyData.cards[currentIndex];
          final bool isCurrentAnswerShown = studyData.isCurrentAnswerShown;
          // *** Get the correct state properties based on the updated StudyStateData ***
          final List<ParsedAnswerLine> currentOrderedAnswerLines = studyData.currentOrderedAnswerLines;
          final List<ChecklistItem> currentChecklistItemsState = studyData.currentChecklistItems;
          // *** End state property changes ***

          final Color liveRatingColor = studyData.currentCardRatingColor == const Color(0xFFbdbdbd) ? _notRatedColor : studyData.currentCardRatingColor;
          final int? lastQuality = studyData.currentCardLastRatingQuality;
          final bool canPressSubmit = isCurrentAnswerShown;

          // Color calculation logic remains the same
          Color finalCardColor; bool lastRatingWasZero = lastQuality != null && lastQuality < 3; if (liveRatingColor == _notRatedColor && lastRatingWasZero) { finalCardColor = _zeroScoreColor; } else if (liveRatingColor == _notRatedColor && lastQuality == null) { finalCardColor = _notRatedColor; } else { finalCardColor = liveRatingColor; }
          Color submitButtonBackgroundColor; if (!canPressSubmit) { submitButtonBackgroundColor = theme.colorScheme.onSurface.withOpacity(0.12); } else { if (liveRatingColor == _notRatedColor && lastRatingWasZero) { submitButtonBackgroundColor = _zeroScoreColor; } else if (liveRatingColor == _notRatedColor && lastQuality == null) { submitButtonBackgroundColor = _notRatedColor; } else { submitButtonBackgroundColor = liveRatingColor; } }
          final bool useWhiteTextOnSubmit = submitButtonBackgroundColor.computeLuminance() < 0.5;
          final Color submitButtonForegroundColor = !canPressSubmit ? theme.colorScheme.onSurface.withOpacity(0.38) : useWhiteTextOnSubmit ? Colors.white : Colors.black87;


          // Build Reveal/Hide Button (logic remains the same)
          Widget revealHideButton;
          if (isCurrentAnswerShown) { revealHideButton = TextButton( onPressed: () => ref.read(studyProvider(widget.folder.id).notifier).toggleAnswerVisibility(), style: TextButton.styleFrom( foregroundColor: _notRatedColor, minimumSize: const Size(double.infinity, 48), padding: const EdgeInsets.symmetric(vertical: 12.0), shape: RoundedRectangleBorder( side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3)), borderRadius: BorderRadius.circular(8.0) ) ), child: const Icon(Icons.keyboard_arrow_up), ); }
          else { final bool useWhiteTextOnReveal = finalCardColor.computeLuminance() < 0.5; final Color revealFgColor = useWhiteTextOnReveal ? Colors.white : Colors.black87; revealHideButton = ElevatedButton( onPressed: () => ref.read(studyProvider(widget.folder.id).notifier).toggleAnswerVisibility(), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12.0), backgroundColor: finalCardColor, foregroundColor: revealFgColor, textStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold) ), child: const Text('REVEAL ANSWER'), ); }


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
                  // *** Pass the new state properties ***
                  orderedAnswerLines: currentOrderedAnswerLines,
                  checklistItemsState: currentChecklistItemsState,
                  // answerMarkdownContent: currentAnswerMarkdown, // REMOVED
                  // *** End passing new properties ***
                  lastRatingQuality: lastQuality,
                  onChecklistChanged: (itemIndex, isChecked) => ref.read(studyProvider(widget.folder.id).notifier).handleChecklistChanged(itemIndex, isChecked),
                  onRatingColorCalculated: (id, color) { ref.read(studyProvider(widget.folder.id).notifier).updateRatingColor(id, color); },
                  onDelete: () => _handleDeleteCard(context, currentCard),
                ),
              ),
              SafeArea( // Footer Buttons (remain the same)
                top: false, left: false, right: false,
                child: Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [ revealHideButton, const SizedBox(height: 8), Visibility( visible: isCurrentAnswerShown, maintainState: true, maintainAnimation: true, maintainSize: true, child: Row( children: [ Expanded( child: OutlinedButton( onPressed: () => _handleSkip(ref), style: OutlinedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 10.0) ), child: const Text('SKIP'), ), ), const SizedBox(width: 8), Expanded( child: ElevatedButton( onPressed: canPressSubmit ? () => _handleSubmitScore(ref) : null, style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 10.0), backgroundColor: submitButtonBackgroundColor, foregroundColor: submitButtonForegroundColor, ), child: const Text('SUBMIT SCORE'), ), ), ], ), ), if (!isCurrentAnswerShown) const SizedBox(height: 48), ], ), ),
              ), // End SafeArea
            ],
          );
        },
      ), // End body: studyStateAsync.when(...)
    ); // End Scaffold
  }
}