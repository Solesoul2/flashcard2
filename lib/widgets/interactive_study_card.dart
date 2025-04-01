// lib/widgets/interactive_study_card.dart
import 'dart:math' show max;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// Import foundation for listEquals if needed elsewhere, though maybe not needed here anymore
// import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

// Import necessary models, screens, and utilities
import '../models/flashcard.dart';
import '../models/folder.dart';
import '../screens/flashcard_edit_page.dart';
import '../utils/helpers.dart';

/// Represents a single item in a checklist derived from flashcard answer.
class ChecklistItem {
  final int originalIndex; // Original index in the parsed list
  final String text;        // Markdown text of the item
  bool isChecked;       // Current checked state

  ChecklistItem({
    required this.originalIndex,
    required this.text,
    this.isChecked = false,
  });

  ChecklistItem copyWith({ bool? isChecked }) {
     return ChecklistItem(
        originalIndex: originalIndex,
        text: text,
        isChecked: isChecked ?? this.isChecked,
     );
  }
}


/// Displays a single flashcard during a study session. Focuses on rendering UI
/// based on provided state. Checklist state management and persistence are delegated
/// to the parent widget via callbacks.
class InteractiveStudyCard extends StatefulWidget {
  final Flashcard flashcard;
  final Folder folder;
  final List<Folder> folderPath; // Path to the current folder
  final int currentCardIndex;
  final int totalCardCount;
  final bool isAnswerShown;        // Whether the answer area is visible
  final List<ChecklistItem> checklistItems; // Parsed checklist items
  final String answerMarkdownContent; // Remaining answer content (non-checklist)
  final int? lastRatingQuality; // Last submitted rating (0-5 or null)

  // Callbacks for parent interaction
  final VoidCallback onDelete;
  final Function(int itemOriginalIndex, bool isChecked) onChecklistChanged; // Reports checkbox changes
  // Callback now includes card ID and the calculated 'live' color
  final Function(int? cardId, Color color)? onRatingColorCalculated; // Reports calculated color for parent UI

  // *** STATIC COLORS (Must match StudyPage) ***
  static const Color notRatedColor = Color(0xFF78909C); // New (BlueGrey[400])
  static const Color zeroScoreColor = Color(0xFFC2185B); // New (Pink[700])
  // ********************************************

  const InteractiveStudyCard({
    required this.flashcard,
    required this.folder,
    required this.folderPath,
    required this.currentCardIndex,
    required this.totalCardCount,
    required this.isAnswerShown,
    required this.checklistItems,
    required this.answerMarkdownContent,
    required this.onDelete,
    required this.onChecklistChanged,
    this.onRatingColorCalculated,
    this.lastRatingQuality,
    Key? key,
  }) : super(key: key);

  @override
  State<InteractiveStudyCard> createState() => _InteractiveStudyCardState();
}

class _InteractiveStudyCardState extends State<InteractiveStudyCard> {
  // Use the NEW notRatedColor as the initial default before calculation
  Color _lastReportedColor = InteractiveStudyCard.notRatedColor;

  // --- Colors & Stops for Progress/Rating ---
  static const List<Color> _progressGradientColors = [
    InteractiveStudyCard.zeroScoreColor, // Start gradient with new "purple"
    Colors.orange,
    Colors.amber,
    Color(0xFF66BB6A),
    Colors.blue,
  ];
  static const List<double> _progressGradientStops = [ 0.0, 0.25, 0.5, 0.75, 1.0 ];
  static const double _minProgressBarValue = 0.015; // Ensures visibility even at 0%

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
       if (mounted) {
         _reportCurrentLiveRatingColor();
       }
    });
  }

  @override
  void didUpdateWidget(covariant InteractiveStudyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Determine if a checklist change occurred (basic comparison)
     bool checklistChanged = widget.checklistItems.length != oldWidget.checklistItems.length;
     if (!checklistChanged) {
         for (int i = 0; i < widget.checklistItems.length; i++) {
             // Compare relevant fields, assuming ChecklistItem has == overridden or compare fields manually
             if (widget.checklistItems[i].isChecked != oldWidget.checklistItems[i].isChecked ||
                 widget.checklistItems[i].text != oldWidget.checklistItems[i].text) {
                 checklistChanged = true;
                 break;
             }
         }
     }


    if (widget.isAnswerShown != oldWidget.isAnswerShown ||
        checklistChanged ||
        widget.flashcard.id != oldWidget.flashcard.id ||
        widget.lastRatingQuality != oldWidget.lastRatingQuality)
    {
      SchedulerBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           _reportCurrentLiveRatingColor();
         }
      });
    }
  }

  // --- Calculation Methods ---

  double _calculateChecklistCompletion() {
    if (widget.checklistItems.isEmpty) return 0.0;
    final checkedCount = widget.checklistItems.where((item) => item.isChecked).length;
    return checkedCount / widget.checklistItems.length;
  }

  bool _isChecklistRated() {
      return widget.checklistItems.any((item) => item.isChecked);
  }

  Color _getLiveRatingColorBasedOnChecks() {
    if (widget.checklistItems.isNotEmpty && !_isChecklistRated()) {
        return InteractiveStudyCard.notRatedColor;
    }
    if (widget.checklistItems.isEmpty) {
        return InteractiveStudyCard.notRatedColor;
    }
    final percentage = _calculateChecklistCompletion();
    final clampedPercentage = percentage.clamp(0.0, 1.0);
    for (int i = 0; i < _progressGradientStops.length - 1; i++) {
      final stop1 = _progressGradientStops[i];
      final stop2 = _progressGradientStops[i + 1];
      if (clampedPercentage >= stop1 && clampedPercentage <= stop2) {
        final range = stop2 - stop1;
        final t = range == 0.0 ? 0.0 : (clampedPercentage - stop1) / range;
        final color1 = _progressGradientColors[i];
        final color2 = _progressGradientColors[i + 1];
        return Color.lerp(color1, color2, t) ?? _progressGradientColors.last;
      }
    }
    return _progressGradientColors.last;
  }

  void _reportCurrentLiveRatingColor() {
     final calculatedLiveColor = _getLiveRatingColorBasedOnChecks();
     if (calculatedLiveColor != _lastReportedColor) {
       _lastReportedColor = calculatedLiveColor;
       SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.onRatingColorCalculated != null) {
            widget.onRatingColorCalculated!(widget.flashcard.id, calculatedLiveColor);
          }
       });
     }
     // Add fallback reporting if needed
     else {
        SchedulerBinding.instance.addPostFrameCallback((_) {
           if (mounted && widget.onRatingColorCalculated != null) {
             widget.onRatingColorCalculated!(widget.flashcard.id, calculatedLiveColor);
           }
        });
     }
  }

  // --- Action Handlers ---

  void _handleCheckboxChanged(int itemOriginalIndex, bool? newValue) {
    if (newValue == null) return;
    widget.onChecklistChanged(itemOriginalIndex, newValue);
  }

  Future<void> _navigateToEdit() async {
    if (widget.flashcard.id == null) return;
    final currentContext = context;
    if (!mounted) return;
    await Navigator.push(
      currentContext,
      MaterialPageRoute(
        builder: (_) => FlashcardEditPage(
          folder: widget.folder,
          flashcard: widget.flashcard,
        ),
      ),
    );
  }

  // --- Build Helpers ---

  String _buildFolderPathString() {
    if (widget.folderPath.isEmpty) return widget.folder.name;
    final pathNames = widget.folderPath.map((f) => f.name).toList();
    if (widget.folderPath.isEmpty || widget.folderPath.last.id != widget.folder.id) {
       pathNames.add(widget.folder.name);
    }
    return pathNames.toSet().toList().join(' > ');
  }


  Widget _buildAnswerSection(BuildContext context) {
     final theme = Theme.of(context);
     final bodyLargeStyle = theme.textTheme.bodyLarge ?? const TextStyle();
     final bodyMediumStyle = theme.textTheme.bodyMedium ?? const TextStyle();

     if (widget.checklistItems.isEmpty && widget.answerMarkdownContent.isEmpty) {
       return Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text( "(No answer content provided)", style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600], fontStyle: FontStyle.italic) ),
       );
     }

     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         if (widget.checklistItems.isNotEmpty)
           ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.checklistItems.length,
              itemBuilder: (context, index) => _buildChecklistItemWidget(context, widget.checklistItems[index], bodyMediumStyle),
           ),
         if (widget.checklistItems.isNotEmpty && widget.answerMarkdownContent.isNotEmpty)
            const SizedBox(height: 12.0),
         if (widget.answerMarkdownContent.isNotEmpty)
           MarkdownBody(
             data: widget.answerMarkdownContent,
             selectable: true,
             onTapLink: (text, href, title) => launchUrlHelper(context, href),
             styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: bodyLargeStyle,
             ),
           ),
       ],
     );
  }

  Widget _buildChecklistItemWidget(BuildContext context, ChecklistItem item, TextStyle textStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24, height: 24,
            child: Checkbox(
              value: item.isChecked,
              onChanged: (bool? newValue) => _handleCheckboxChanged(item.originalIndex, newValue),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1.0),
              child: MarkdownBody(
                 data: item.text.isEmpty ? "(empty)" : item.text,
                 selectable: true,
                 onTapLink: (text, href, title) => launchUrlHelper(context, href),
                 styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                   p: textStyle,
                   listBulletPadding: EdgeInsets.zero, // Reset list padding
                 ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Main Build Method ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    // 1. Get the *live* rating color based on current checkbox interactions
    final Color liveRatingColor = _getLiveRatingColorBasedOnChecks();

    // 2. Apply Override Logic for the Top Bar Color (incorporating lastRatingQuality)
    //    *** THIS NOW APPLIES REGARDLESS OF isAnswerShown ***
    Color finalTopBarColor;
    final int? lastQuality = widget.lastRatingQuality;
    bool lastRatingWasZero = lastQuality != null && lastQuality < 3;

    if (liveRatingColor == InteractiveStudyCard.notRatedColor && lastRatingWasZero) {
        finalTopBarColor = InteractiveStudyCard.zeroScoreColor; // Use new "purple"
    } else if (liveRatingColor == InteractiveStudyCard.notRatedColor && lastQuality == null) {
        finalTopBarColor = InteractiveStudyCard.notRatedColor; // Use new grey
    } else {
        finalTopBarColor = liveRatingColor; // Use live gradient color
    }

    // 3. Report the *live* color back to the parent
    _reportCurrentLiveRatingColor();

    // 4. Determine text contrast based on the *final* top bar color
    final bool useWhiteTextOnTopBar = finalTopBarColor.computeLuminance() < 0.5;
    final Color contrastTextColorOnTopBar = useWhiteTextOnTopBar ? Colors.white : Colors.black87;

    // 5. Calculate progress bar value and visibility
    //    *** UPDATED VISIBILITY LOGIC ***
    final bool shouldShowProgressBar = widget.checklistItems.isNotEmpty &&
                                      (_isChecklistRated() || lastQuality != null); // Show if rated now OR rated previously

    double completionPercentage = _calculateChecklistCompletion();
    double progressBarValue = (completionPercentage <= 0.0 && shouldShowProgressBar)
        ? _minProgressBarValue // Show minimal bar if 0% but should be visible
        : completionPercentage;


    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // --- Top Bar ---
            Container(
              color: finalTopBarColor, // Apply the final calculated color
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text(
                     'Card ${widget.currentCardIndex} of ${widget.totalCardCount}',
                     style: textTheme.bodyMedium?.copyWith(color: contrastTextColorOnTopBar),
                   ),
                   Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       IconButton(
                         icon: Icon(Icons.edit_outlined, color: contrastTextColorOnTopBar),
                         tooltip: 'Edit Flashcard',
                         iconSize: 20.0,
                         constraints: const BoxConstraints(),
                         padding: const EdgeInsets.symmetric(horizontal: 8),
                         onPressed: _navigateToEdit,
                       ),
                       IconButton(
                         icon: Icon(Icons.delete_outline, color: contrastTextColorOnTopBar),
                         tooltip: 'Delete Flashcard',
                         iconSize: 20.0,
                         constraints: const BoxConstraints(),
                         padding: const EdgeInsets.symmetric(horizontal: 8),
                         onPressed: widget.onDelete,
                       ),
                     ],
                   ),
                 ],
               ),
            ),

            // --- Scrollable Middle Section ---
            Expanded(
              child: ListView( // Use ListView for scrollable content
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Folder Path
                  if (widget.folderPath.isNotEmpty || widget.folder.id != null)
                     Padding(
                       padding: const EdgeInsets.only(bottom: 16.0),
                       child: Text(
                          _buildFolderPathString(),
                          style: textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                     ),
                  // Question Area
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: MarkdownBody(
                       data: widget.flashcard.question.isEmpty ? "(No question)" : widget.flashcard.question,
                       selectable: true,
                       onTapLink: (text, href, title) => launchUrlHelper(context, href),
                       styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                         p: textTheme.headlineSmall,
                       ),
                    ),
                  ),

                  // Divider only shown if answer is visible
                  if (widget.isAnswerShown) const Divider(height: 24.0, thickness: 1.0),

                  // Answer Area (Conditional)
                  if (widget.isAnswerShown)
                     _buildAnswerSection(context),

                  // Checklist Progress Bar (Conditional)
                  // *** USE UPDATED VISIBILITY ***
                  Visibility(
                    visible: shouldShowProgressBar,
                    child: Padding(
                       padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
                       child: ClipRRect(
                         borderRadius: BorderRadius.circular(8.0),
                         child: SizedBox(
                           height: 8.0,
                           child: LinearProgressIndicator(
                             // *** USE UPDATED VALUE ***
                             value: progressBarValue,
                             valueColor: AlwaysStoppedAnimation<Color>(finalTopBarColor),
                             backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5), // Slightly transparent background
                           ),
                         ),
                       ),
                     ),
                  ), // End Progress Bar Visibility
                ], // End ListView children
              ), // End ListView
            ), // End Expanded scrollable area
          ], // End Outer Column
        ), // End Card
      ), // End Outer Padding
    );
  }
}

// Removed the custom listEquals helper function