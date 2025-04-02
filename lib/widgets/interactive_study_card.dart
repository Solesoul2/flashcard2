// lib/widgets/interactive_study_card.dart
import 'dart:math' show max;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_markdown/flutter_markdown.dart'; // Still needed for Answer section

// Import necessary models, screens, utilities, and the new structures from study_notifier
import '../models/flashcard.dart';
import '../models/folder.dart';
import '../screens/flashcard_edit_page.dart';
import '../utils/helpers.dart';
import '../providers/study_notifier.dart'; // Import for ParsedAnswerLine, AnswerLineType

// ChecklistItem class definition remains the same
class ChecklistItem {
  final int originalIndex; final String text; bool isChecked;
  ChecklistItem({ required this.originalIndex, required this.text, this.isChecked = false });
  ChecklistItem copyWith({ bool? isChecked }) { return ChecklistItem( originalIndex: originalIndex, text: text, isChecked: isChecked ?? this.isChecked ); }

  // Add equality operators for didUpdateWidget comparison if needed
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChecklistItem &&
          runtimeType == other.runtimeType &&
          originalIndex == other.originalIndex &&
          text == other.text &&
          isChecked == other.isChecked;

  @override
  int get hashCode => originalIndex.hashCode ^ text.hashCode ^ isChecked.hashCode;
}

/// Displays a single flashcard during a study session. Focuses on rendering UI
/// based on provided state. Checklist state management and persistence are delegated
/// to the parent widget via callbacks.
class InteractiveStudyCard extends StatefulWidget {
  final Flashcard flashcard;
  final Folder folder;
  final List<Folder> folderPath;
  final int currentCardIndex;
  final int totalCardCount;
  final bool isAnswerShown;
  // Accept new ordered list and separate checklist state
  final List<ParsedAnswerLine> orderedAnswerLines; // NEW: Combined list for rendering order
  final List<ChecklistItem> checklistItemsState; // Contains ALL checklist items for this card, managed by notifier
  final int? lastRatingQuality;

  // Callbacks
  final VoidCallback onDelete;
  final Function(int itemOriginalIndex, bool isChecked) onChecklistChanged;
  final Function(int? cardId, Color color)? onRatingColorCalculated;
  // *** ADDED: Callback for when editing is complete ***
  final Future<void> Function()? onEditComplete;

  // Constants remain the same
  static const Color notRatedColor = Color(0xFF78909C);
  static const Color zeroScoreColor = Color(0xFFC2185B);

  const InteractiveStudyCard({
    required this.flashcard, required this.folder, required this.folderPath,
    required this.currentCardIndex, required this.totalCardCount, required this.isAnswerShown,
    required this.orderedAnswerLines, // NEW
    required this.checklistItemsState, // Keep for state
    required this.onDelete, required this.onChecklistChanged,
    this.onRatingColorCalculated,
    this.lastRatingQuality,
    this.onEditComplete, // *** ADDED: Include in constructor ***
    Key? key,
  }) : super(key: key);

  @override
  State<InteractiveStudyCard> createState() => _InteractiveStudyCardState();
}

class _InteractiveStudyCardState extends State<InteractiveStudyCard> {
  Color _lastReportedColor = InteractiveStudyCard.notRatedColor;
  static const List<Color> _progressGradientColors = [ InteractiveStudyCard.zeroScoreColor, Colors.orange, Colors.amber, Color(0xFF66BB6A), Colors.blue ];
  static const List<double> _progressGradientStops = [ 0.0, 0.25, 0.5, 0.75, 1.0 ];
  static const double _minProgressBarValue = 0.015;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { _reportCurrentLiveRatingColor(); } }); }

  // didUpdateWidget checks if checklistItemsState changed using listEquals
  @override
  void didUpdateWidget(covariant InteractiveStudyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if the actual checklist state list changed (content or order might change)
    bool checklistStateListChanged = !listEquals(widget.checklistItemsState, oldWidget.checklistItemsState);

    // Also check if the rendering order list changed
    bool orderedLinesChanged = !listEquals(widget.orderedAnswerLines, oldWidget.orderedAnswerLines);

    if (widget.isAnswerShown != oldWidget.isAnswerShown ||
        checklistStateListChanged || // Use the new check
        orderedLinesChanged ||
        widget.flashcard.id != oldWidget.flashcard.id ||
        widget.lastRatingQuality != oldWidget.lastRatingQuality) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
         if (mounted) { _reportCurrentLiveRatingColor(); }
      });
    }
  }


  // Calculation methods now use checklistItemsState (remain the same functionally)
  double _calculateChecklistCompletion() { if (widget.checklistItemsState.isEmpty) return 0.0; final checkedCount = widget.checklistItemsState.where((item) => item.isChecked).length; return checkedCount / widget.checklistItemsState.length; }
  bool _isChecklistRated() { return widget.checklistItemsState.any((item) => item.isChecked); }
  Color _getLiveRatingColorBasedOnChecks() { if (widget.checklistItemsState.isNotEmpty && !_isChecklistRated()) { return InteractiveStudyCard.notRatedColor; } if (widget.checklistItemsState.isEmpty) { return InteractiveStudyCard.notRatedColor; } final percentage = _calculateChecklistCompletion(); final clampedPercentage = percentage.clamp(0.0, 1.0); for (int i = 0; i < _progressGradientStops.length - 1; i++) { final stop1 = _progressGradientStops[i]; final stop2 = _progressGradientStops[i + 1]; if (clampedPercentage >= stop1 && clampedPercentage <= stop2) { final range = stop2 - stop1; final t = range == 0.0 ? 0.0 : (clampedPercentage - stop1) / range; final color1 = _progressGradientColors[i]; final color2 = _progressGradientColors[i + 1]; return Color.lerp(color1, color2, t) ?? _progressGradientColors.last; } } return _progressGradientColors.last; }
  void _reportCurrentLiveRatingColor() { final calculatedLiveColor = _getLiveRatingColorBasedOnChecks(); if (calculatedLiveColor != _lastReportedColor) { _lastReportedColor = calculatedLiveColor; SchedulerBinding.instance.addPostFrameCallback((_) { if (mounted && widget.onRatingColorCalculated != null) { widget.onRatingColorCalculated!(widget.flashcard.id, calculatedLiveColor); } }); } else { /* No need to report if color hasn't changed, but the logic in didUpdateWidget might still call this. Let's remove the redundant report */ } }

  // Action Handler for Checkbox
  void _handleCheckboxChanged(int itemOriginalIndex, bool? newValue) { if (newValue == null) return; widget.onChecklistChanged(itemOriginalIndex, newValue); }

  // *** MODIFIED: _navigateToEdit ***
  // Now awaits the result and calls onEditComplete if successful
  Future<void> _navigateToEdit() async {
    if (widget.flashcard.id == null) return;
    final currentContext = context; // Capture context before async gap.
    if (!mounted) return;

    // Await the result from the edit page
    final result = await Navigator.push(
      currentContext,
      MaterialPageRoute(
        builder: (_) => FlashcardEditPage(
          folder: widget.folder,
          flashcard: widget.flashcard,
        ),
      ),
    );

    // If the result is true (save successful), call the callback
    // Check mounted again after await
    if (result == true && widget.onEditComplete != null && mounted) {
        await widget.onEditComplete!();
    }
  }
  // *** END MODIFICATION ***

  // Build Helpers (_buildFolderPathString remains same)
  String _buildFolderPathString() { if (widget.folderPath.isEmpty) return widget.folder.name; final pathNames = widget.folderPath.map((f) => f.name).toList(); if (widget.folderPath.isEmpty || widget.folderPath.last.id != widget.folder.id) { pathNames.add(widget.folder.name); } return pathNames.toSet().toList().join(' > '); }

  // *** MODIFIED: _buildChecklistItemWidget ***
  // Applies styling based on item.isChecked
  Widget _buildChecklistItemWidget(BuildContext context, ChecklistItem item, TextStyle defaultStyle) {
    final theme = Theme.of(context);
    // Define styles based on checked state
    final TextStyle textStyle = item.isChecked
      ? defaultStyle.copyWith(
          color: Colors.grey[600], // Grey color when checked
          decoration: TextDecoration.lineThrough, // Strikethrough when checked
        )
      : defaultStyle; // Default style when not checked

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: item.isChecked,
              onChanged: (bool? newValue) => _handleCheckboxChanged(item.originalIndex, newValue),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              // Optional: Use theme colors for checkbox
              // activeColor: theme.primaryColor,
              // checkColor: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1.0), // Adjust alignment with checkbox
              child: MarkdownBody(
                data: item.text.isEmpty ? "(empty)" : item.text,
                selectable: true,
                onTapLink: (text, href, title) => launchUrlHelper(context, href),
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: textStyle, // Apply the conditional text style
                  listBulletPadding: EdgeInsets.zero, // Avoid extra padding
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // *** REWRITTEN: _buildAnswerSection ***
  // Groups consecutive checklist items, sorts them, and applies styling
  Widget _buildAnswerSection(BuildContext context) {
    final theme = Theme.of(context);
    final bodyLargeStyle = theme.textTheme.bodyLarge ?? const TextStyle();
    final bodyMediumStyle = theme.textTheme.bodyMedium ?? const TextStyle(); // Default for checklist
    final orderedLines = widget.orderedAnswerLines;

    if (orderedLines.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          "(No answer content provided)",
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600], fontStyle: FontStyle.italic),
        ),
      );
    }

    List<Widget> contentWidgets = [];
    List<ParsedAnswerLine> currentChecklistGroup = [];

    void renderChecklistGroup() {
      if (currentChecklistGroup.isNotEmpty) {
        // 1. Get the state objects corresponding to the current group
        List<ChecklistItem> groupStates = [];
        for (var line in currentChecklistGroup) {
          if (line.originalChecklistIndex != null) {
            // Use firstWhere or provide a fallback if the item might be missing (though it shouldn't be)
            final stateItem = widget.checklistItemsState.firstWhere(
                (s) => s.originalIndex == line.originalChecklistIndex,
                orElse: () {
                     print("Warning: Checklist state item not found for original index ${line.originalChecklistIndex}");
                     // Create a temporary item to avoid crashing, but log the issue
                     return ChecklistItem(originalIndex: line.originalChecklistIndex!, text: line.textContent, isChecked: false);
                 });
            groupStates.add(stateItem);
          }
        }

        // 2. Sort the state objects (checked items last) - this is now redundant if notifier sorts
         // groupStates.sort((a, b) {
         //   if (a.isChecked == b.isChecked) return 0; // Keep original relative order if same state
         //   return a.isChecked ? 1 : -1; // Checked items go to the end
         // });

        // 3. Render the checklist items using their state (already sorted by the notifier)
        for (var sortedItemState in widget.checklistItemsState.where((s) => currentChecklistGroup.any((line) => line.originalChecklistIndex == s.originalIndex))) {
           contentWidgets.add(_buildChecklistItemWidget(context, sortedItemState, bodyMediumStyle));
        }
        currentChecklistGroup.clear();
      }
    }

    for (final line in orderedLines) {
      if (line.type == AnswerLineType.checklist) {
        currentChecklistGroup.add(line);
      } else {
        // Render any pending checklist group first
        renderChecklistGroup();
        // Render the text line
        if (line.textContent.trim().isEmpty) {
          contentWidgets.add(const SizedBox(height: 8.0)); // Represents empty line spacing
        } else {
          contentWidgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: MarkdownBody(
                data: line.textContent,
                selectable: true,
                onTapLink: (text, href, title) => launchUrlHelper(context, href),
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(p: bodyLargeStyle),
              ),
            ),
          );
        }
      }
    }
    // Render any remaining checklist group at the end
    renderChecklistGroup();

    // Use Column instead of ListView.builder as we build all widgets at once
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: contentWidgets,
    );
  }


  // --- Main Build Method --- (Layout remains the same, uses the new _buildAnswerSection)
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    // Calculation logic for colors and progress bar (remains the same)
    final Color liveRatingColor = _getLiveRatingColorBasedOnChecks(); Color finalTopBarColor; final int? lastQuality = widget.lastRatingQuality; bool lastRatingWasZero = lastQuality != null && lastQuality < 3; if (liveRatingColor == InteractiveStudyCard.notRatedColor && lastRatingWasZero) { finalTopBarColor = InteractiveStudyCard.zeroScoreColor; } else if (liveRatingColor == InteractiveStudyCard.notRatedColor && lastQuality == null) { finalTopBarColor = InteractiveStudyCard.notRatedColor; } else { finalTopBarColor = liveRatingColor; } _reportCurrentLiveRatingColor(); final bool useWhiteTextOnTopBar = finalTopBarColor.computeLuminance() < 0.5; final Color contrastTextColorOnTopBar = useWhiteTextOnTopBar ? Colors.white : Colors.black87;
    final bool shouldShowProgressBar = widget.checklistItemsState.isNotEmpty && (_isChecklistRated() || lastQuality != null); double completionPercentage = _calculateChecklistCompletion(); double progressBarValue = (completionPercentage <= 0.0 && shouldShowProgressBar) ? _minProgressBarValue : completionPercentage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Top Bar (remains the same)
            Container( color: finalTopBarColor, padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text( 'Card ${widget.currentCardIndex} of ${widget.totalCardCount}', style: textTheme.bodyMedium?.copyWith(color: contrastTextColorOnTopBar), ), Row( mainAxisSize: MainAxisSize.min, children: [ IconButton( icon: Icon(Icons.edit_outlined, color: contrastTextColorOnTopBar), tooltip: 'Edit Flashcard', iconSize: 20.0, constraints: const BoxConstraints(), padding: const EdgeInsets.symmetric(horizontal: 8), onPressed: _navigateToEdit, ), IconButton( icon: Icon(Icons.delete_outline, color: contrastTextColorOnTopBar), tooltip: 'Delete Flashcard', iconSize: 20.0, constraints: const BoxConstraints(), padding: const EdgeInsets.symmetric(horizontal: 8), onPressed: widget.onDelete, ), ], ), ], ), ),
            // Scrollable Middle Section
            Expanded(
              child: ListView( // Keep ListView for overall scrollability if content overflows
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Folder Path (remains the same)
                  if (widget.folderPath.isNotEmpty || widget.folder.id != null) Padding( padding: const EdgeInsets.only(bottom: 16.0), child: Text( _buildFolderPathString(), style: textTheme.bodySmall?.copyWith(color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis, ), ),
                  // Question Area (remains the same)
                  Padding( padding: const EdgeInsets.only(bottom: 16.0), child: Text( widget.flashcard.question.isEmpty ? "(No question)" : widget.flashcard.question, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500), ), ),
                  // Divider (remains the same)
                  if (widget.isAnswerShown) const Divider(height: 24.0, thickness: 1.0),

                  // *** Answer Area (NOW uses the rewritten _buildAnswerSection) ***
                  if (widget.isAnswerShown)
                    _buildAnswerSection(context), // This handles text and sorted checklist

                  // Checklist Progress Bar (remains the same)
                  Visibility( visible: shouldShowProgressBar, child: Padding( padding: const EdgeInsets.only(top: 24.0, bottom: 8.0), child: ClipRRect( borderRadius: BorderRadius.circular(8.0), child: SizedBox( height: 8.0, child: LinearProgressIndicator( value: progressBarValue, valueColor: AlwaysStoppedAnimation<Color>(finalTopBarColor), backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5), ), ), ), ), ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}