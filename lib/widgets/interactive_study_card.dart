// lib/widgets/interactive_study_card.dart
import 'dart:math' show max, min;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_markdown/flutter_markdown.dart';

// Import necessary models, screens, utilities, and the structures from study_notifier
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
/// based on provided state, including conditional visibility based on study settings.
class InteractiveStudyCard extends StatefulWidget {
  final Flashcard flashcard;
  final Folder folder;
  final List<Folder> folderPath;
  final int currentCardIndex;
  final int totalCardCount;
  final bool isAnswerShown;
  final List<ParsedAnswerLine> orderedAnswerLines;
  final List<ChecklistItem> checklistItemsState; // Sorted list managed by notifier
  final int? lastRatingQuality;
  final bool setting1Active; // Hide unmarked text unless followed by checkbox
  final bool setting2Active; // Show previously checked items always

  // Callbacks
  final VoidCallback onDelete;
  final Function(int itemOriginalIndex, bool isChecked) onChecklistChanged;
  final Function(int? cardId, Color color)? onRatingColorCalculated;
  final Future<void> Function()? onEditComplete;

  // Constants remain the same
  static const Color notRatedColor = Color(0xFF78909C);
  static const Color zeroScoreColor = Color(0xFFC2185B);

  const InteractiveStudyCard({
    required this.flashcard, required this.folder, required this.folderPath,
    required this.currentCardIndex, required this.totalCardCount, required this.isAnswerShown,
    required this.orderedAnswerLines,
    required this.checklistItemsState,
    required this.onDelete, required this.onChecklistChanged,
    this.onRatingColorCalculated,
    this.lastRatingQuality,
    this.onEditComplete,
    required this.setting1Active,
    required this.setting2Active,
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

  @override
  void didUpdateWidget(covariant InteractiveStudyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool checklistStateListChanged = !listEquals(widget.checklistItemsState, oldWidget.checklistItemsState);
    bool orderedLinesChanged = !listEquals(widget.orderedAnswerLines, oldWidget.orderedAnswerLines);
    bool settingsChanged = widget.setting1Active != oldWidget.setting1Active || widget.setting2Active != oldWidget.setting2Active;

    if (widget.isAnswerShown != oldWidget.isAnswerShown ||
        checklistStateListChanged ||
        orderedLinesChanged ||
        settingsChanged ||
        widget.flashcard.id != oldWidget.flashcard.id ||
        widget.lastRatingQuality != oldWidget.lastRatingQuality) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
         if (mounted) { _reportCurrentLiveRatingColor(); }
      });
    }
  }


  // Calculation methods remain the same
  double _calculateChecklistCompletion() { if (widget.checklistItemsState.isEmpty) return 0.0; final checkedCount = widget.checklistItemsState.where((item) => item.isChecked).length; return checkedCount / widget.checklistItemsState.length; }
  bool _isChecklistRated() { return widget.checklistItemsState.any((item) => item.isChecked); }
  Color _getLiveRatingColorBasedOnChecks() { if (widget.checklistItemsState.isNotEmpty && !_isChecklistRated()) { return InteractiveStudyCard.notRatedColor; } if (widget.checklistItemsState.isEmpty) { return InteractiveStudyCard.notRatedColor; } final percentage = _calculateChecklistCompletion(); final clampedPercentage = percentage.clamp(0.0, 1.0); for (int i = 0; i < _progressGradientStops.length - 1; i++) { final stop1 = _progressGradientStops[i]; final stop2 = _progressGradientStops[i + 1]; if (clampedPercentage >= stop1 && clampedPercentage <= stop2) { final range = stop2 - stop1; final t = range == 0.0 ? 0.0 : (clampedPercentage - stop1) / range; final color1 = _progressGradientColors[i]; final color2 = _progressGradientColors[i + 1]; return Color.lerp(color1, color2, t) ?? _progressGradientColors.last; } } return _progressGradientColors.last; }
  void _reportCurrentLiveRatingColor() { final calculatedLiveColor = _getLiveRatingColorBasedOnChecks(); if (calculatedLiveColor != _lastReportedColor) { _lastReportedColor = calculatedLiveColor; SchedulerBinding.instance.addPostFrameCallback((_) { if (mounted && widget.onRatingColorCalculated != null) { widget.onRatingColorCalculated!(widget.flashcard.id, calculatedLiveColor); } }); } }

  // Action Handler for Checkbox remains the same
  void _handleCheckboxChanged(int itemOriginalIndex, bool? newValue) { if (newValue == null) return; widget.onChecklistChanged(itemOriginalIndex, newValue); }

  // _navigateToEdit remains the same
  Future<void> _navigateToEdit() async {
    if (widget.flashcard.id == null) return;
    final currentContext = context;
    if (!mounted) return;
    final result = await Navigator.push( currentContext, MaterialPageRoute( builder: (_) => FlashcardEditPage( folder: widget.folder, flashcard: widget.flashcard, ), ), );
    if (result == true && widget.onEditComplete != null && mounted) { await widget.onEditComplete!(); }
  }

  // Build Helpers
  String _buildFolderPathString() { if (widget.folderPath.isEmpty) return widget.folder.name; final pathNames = widget.folderPath.map((f) => f.name).toList(); if (widget.folderPath.isEmpty || widget.folderPath.last.id != widget.folder.id) { pathNames.add(widget.folder.name); } return pathNames.toSet().toList().join(' > '); }

  // _buildChecklistItemWidget (applies visual styling based on checked) remains the same
  Widget _buildChecklistItemWidget(BuildContext context, ChecklistItem item, TextStyle defaultStyle) {
    final theme = Theme.of(context);
    final TextStyle textStyle = item.isChecked
      ? defaultStyle.copyWith( color: Colors.grey[600], decoration: TextDecoration.lineThrough, )
      : defaultStyle;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox( width: 24, height: 24, child: Checkbox( value: item.isChecked, onChanged: (bool? newValue) => _handleCheckboxChanged(item.originalIndex, newValue), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, ), ),
          const SizedBox(width: 8.0),
          Expanded( child: Padding( padding: const EdgeInsets.only(top: 1.0), child: MarkdownBody( data: item.text.isEmpty ? "(empty)" : item.text, selectable: true, onTapLink: (text, href, title) => launchUrlHelper(context, href), styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith( p: textStyle, listBulletPadding: EdgeInsets.zero, ), ), ), ),
        ],
      ),
    );
  }

  // --- MODIFIED: Build Unchecked Boxes Preview (now takes theme) ---
  // This widget itself doesn't need visibility logic anymore,
  // it will be inserted conditionally by _buildAnswerSection.
  Widget _buildUncheckedBoxesPreview(BuildContext context, ThemeData theme) {
    final uncheckedItems = widget.checklistItemsState.where((item) => !item.isChecked).toList();

    // This check might be redundant now but safe to keep
    if (uncheckedItems.isEmpty) { // || widget.isAnswerShown) { Removed isAnswerShown check
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 0.0, bottom: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(uncheckedItems.length, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24, height: 24,
                  child: Checkbox(
                    value: false, onChanged: null, // Disabled
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    fillColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.disabled) ? Colors.grey.withOpacity(0.1) : null),
                    side: MaterialStateBorderSide.resolveWith((states) => BorderSide(color: states.contains(MaterialState.disabled) ? Colors.grey[400]! : theme.colorScheme.onSurface.withOpacity(0.6))),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
  // --- End MODIFICATION ---


  // --- REWRITTEN: _buildAnswerSection (Single Pass + Integrated Preview) ---
  Widget _buildAnswerSection(BuildContext context) {
    final theme = Theme.of(context);
    final bodyLargeStyle = theme.textTheme.bodyLarge ?? const TextStyle();
    final bodyMediumStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final orderedLines = widget.orderedAnswerLines;

    if (orderedLines.isEmpty) {
      return Container( padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text( "(No answer content provided)", style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600], fontStyle: FontStyle.italic), ), );
    }

    final bool allChecklistItemsChecked = widget.checklistItemsState.isNotEmpty && widget.checklistItemsState.every((item) => item.isChecked);

    List<Widget> finalWidgets = [];
    List<ParsedAnswerLine> groupCollector = [];
    bool previewInserted = false; // Flag to insert preview only once

    // Helper to render collected checklist items with visibility logic
    void renderGroupFromCollector() {
      if (groupCollector.isNotEmpty) {
        var itemsInGroup = widget.checklistItemsState.where(
            (s) => groupCollector.any((line) => line.originalChecklistIndex == s.originalIndex)
        ).toList();

        for (final sortedItemState in itemsInGroup) {
          bool alwaysVisibleBasedOnSettings = widget.setting2Active && sortedItemState.isChecked;
          bool isVisible = widget.isAnswerShown || (!allChecklistItemsChecked && alwaysVisibleBasedOnSettings);
          final checklistWidget = _buildChecklistItemWidget(context, sortedItemState, bodyMediumStyle);
          finalWidgets.add(Visibility( visible: isVisible, maintainState: true, maintainAnimation: true, maintainSize: false, child: checklistWidget, ));
        }
        groupCollector.clear();
      }
    }

    // Iterate through original lines, build widgets, apply visibility directly
    for (int i = 0; i < orderedLines.length; i++) {
      final line = orderedLines[i];

      if (line.type == AnswerLineType.text) {
        renderGroupFromCollector(); // Render any preceding checklist group

        bool alwaysVisibleBasedOnSettings = false;
        if (widget.setting1Active) {
            bool isFollowedByCheckbox = false;
            for (int j = i + 1; j < orderedLines.length; j++) {
                final nextLine = orderedLines[j];
                if (nextLine.type == AnswerLineType.checklist) { isFollowedByCheckbox = true; break; }
                if (nextLine.type == AnswerLineType.text && nextLine.textContent.trim().isNotEmpty) { isFollowedByCheckbox = false; break; }
            }
            if (isFollowedByCheckbox) { alwaysVisibleBasedOnSettings = true; }
        }

        bool isVisible = widget.isAnswerShown || (!allChecklistItemsChecked && alwaysVisibleBasedOnSettings);
        Widget textWidget;
         if (line.textContent.trim().isEmpty) { textWidget = const SizedBox(height: 8.0); }
         else { textWidget = Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: MarkdownBody( data: line.textContent, selectable: true, onTapLink: (text, href, title) => launchUrlHelper(context, href), styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(p: bodyLargeStyle), ), ); }
         finalWidgets.add(Visibility( visible: isVisible, maintainState: true, maintainAnimation: true, maintainSize: false, child: textWidget, ));

      } else { // line.type == AnswerLineType.checklist
        // *** Insert Preview before the FIRST checklist item is processed ***
        if (!previewInserted && !widget.isAnswerShown) {
           final previewWidget = _buildUncheckedBoxesPreview(context, theme);
           // Add preview only if it's not an empty SizedBox
           if (previewWidget is! SizedBox || (previewWidget.height != 0 && previewWidget.width != 0)) {
               finalWidgets.add(previewWidget);
           }
           previewInserted = true; // Ensure it's added only once
        }
        // Collect checklist lines
        groupCollector.add(line);
      }
    }
    renderGroupFromCollector(); // Render any trailing checklist group

    return Column( crossAxisAlignment: CrossAxisAlignment.start, children: finalWidgets );
  }


  // Main Build Method (structure remains the same, no separate preview call)
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    // Calculation logic
    final Color liveRatingColor = _getLiveRatingColorBasedOnChecks();
    Color finalTopBarColor;
    final int? lastQuality = widget.lastRatingQuality;
    bool lastRatingWasZero = lastQuality != null && lastQuality < 3;
    if (liveRatingColor == InteractiveStudyCard.notRatedColor && lastRatingWasZero) { finalTopBarColor = InteractiveStudyCard.zeroScoreColor; }
    else if (liveRatingColor == InteractiveStudyCard.notRatedColor && lastQuality == null) { finalTopBarColor = InteractiveStudyCard.notRatedColor; }
    else { finalTopBarColor = liveRatingColor; }
    _reportCurrentLiveRatingColor();

    final bool useWhiteTextOnTopBar = finalTopBarColor.computeLuminance() < 0.5;
    final Color contrastTextColorOnTopBar = useWhiteTextOnTopBar ? Colors.white : Colors.black87;

    final bool shouldShowProgressBar = widget.checklistItemsState.isNotEmpty && (_isChecklistRated() || lastQuality != null);
    double completionPercentage = _calculateChecklistCompletion();
    double progressBarValue = (completionPercentage <= 0.0 && shouldShowProgressBar) ? _minProgressBarValue : completionPercentage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Top Bar
            Container( color: finalTopBarColor, padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text( 'Card ${widget.currentCardIndex} of ${widget.totalCardCount}', style: textTheme.bodyMedium?.copyWith(color: contrastTextColorOnTopBar), ), Row( mainAxisSize: MainAxisSize.min, children: [ IconButton( icon: Icon(Icons.edit_outlined, color: contrastTextColorOnTopBar), tooltip: 'Edit Flashcard', iconSize: 20.0, constraints: const BoxConstraints(), padding: const EdgeInsets.symmetric(horizontal: 8), onPressed: _navigateToEdit, ), IconButton( icon: Icon(Icons.delete_outline, color: contrastTextColorOnTopBar), tooltip: 'Delete Flashcard', iconSize: 20.0, constraints: const BoxConstraints(), padding: const EdgeInsets.symmetric(horizontal: 8), onPressed: widget.onDelete, ), ], ), ], ), ),
            // Scrollable Middle Section
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Folder Path
                  if (widget.folderPath.isNotEmpty || widget.folder.id != null) Padding( padding: const EdgeInsets.only(bottom: 16.0), child: Text( _buildFolderPathString(), style: textTheme.bodySmall?.copyWith(color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis, ), ),
                  // Question Area
                  Padding( padding: const EdgeInsets.only(bottom: 8.0),
                   child: Text( widget.flashcard.question.isEmpty ? "(No question)" : widget.flashcard.question, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500), ), ),

                  // Divider
                  const Divider(height: 24.0, thickness: 1.0),

                  // --- REMOVED separate preview call ---
                  // _buildUncheckedBoxesPreview(context),

                  // Answer Area (now includes preview logic internally)
                  _buildAnswerSection(context),

                  // Checklist Progress Bar
                  Visibility(
                    visible: shouldShowProgressBar,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: SizedBox(
                          height: 8.0,
                          child: LinearProgressIndicator(
                            value: progressBarValue,
                            valueColor: AlwaysStoppedAnimation<Color>(finalTopBarColor),
                            backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}