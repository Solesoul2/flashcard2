// lib/screens/flashcard_edit_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod

// Import necessary models, providers, and services
import '../models/flashcard.dart';
import '../models/folder.dart';
// Removed direct DB Helper import
// import '../services/database_helper.dart';
import '../providers/service_providers.dart'; // Import service providers

/// A page providing a form to add a new flashcard or edit an existing one
/// within a specific folder context (including 'Uncategorized').
// Change to ConsumerStatefulWidget
class FlashcardEditPage extends ConsumerStatefulWidget {
  final Folder folder;
  final Flashcard? flashcard;

  const FlashcardEditPage({
    required this.folder,
    this.flashcard,
    Key? key,
  }) : super(key: key);

  @override
  // Change to ConsumerState
  ConsumerState<FlashcardEditPage> createState() => _FlashcardEditPageState();
}

// Change to ConsumerState
class _FlashcardEditPageState extends ConsumerState<FlashcardEditPage> {
  // Removed direct instantiation
  // final DatabaseHelper _dbHelper = DatabaseHelper(); // <-- REMOVED

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _questionController;
  late TextEditingController _answerController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.flashcard?.question ?? '');
    _answerController = TextEditingController(text: widget.flashcard?.answer ?? '');
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  /// Handles saving the flashcard (insert or update) using the provider.
  Future<void> _saveFlashcard() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() { _isSaving = true; });

    final String question = _questionController.text.trim();
    final String answer = _answerController.text.trim();

    Flashcard cardToSave;
    if (widget.flashcard == null) {
      cardToSave = Flashcard(
        question: question,
        answer: answer,
        folderId: widget.folder.id,
      );
    } else {
      cardToSave = widget.flashcard!.copyWith(
        question: question,
        answer: answer,
      );
    }

    final currentContext = context; // Capture context before async gap.
    if (!mounted) return;

    try {
      // Get DatabaseHelper instance via provider
      final dbHelper = await ref.read(databaseHelperProvider.future);

      String message;
      if(widget.flashcard == null) {
         await dbHelper.insertFlashcard(cardToSave);
         message = 'Flashcard added!';
      } else {
         await dbHelper.updateFlashcard(cardToSave);
         message = 'Flashcard updated!';
      }

      if(mounted) {
         ScaffoldMessenger.of(currentContext).showSnackBar(SnackBar(content: Text(message)));
         Navigator.pop(currentContext, true); // Return true to signal success
      }
    } catch (e) {
       print("Error saving flashcard: $e");
        if(mounted) {
           ScaffoldMessenger.of(currentContext).showSnackBar(
             SnackBar(content: Text('Error saving flashcard: $e'), backgroundColor: Colors.red)
           );
           setState(() { _isSaving = false; }); // Reset saving flag on error
        }
    }
    // No finally needed if popping on success
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.flashcard != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Flashcard' : 'Add Flashcard'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Icon(Icons.save_outlined),
            tooltip: 'Save Flashcard',
            onPressed: _isSaving ? null : _saveFlashcard, // Uses updated method
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
           key: _formKey,
           child: ListView(
             children: [
               TextFormField(
                 controller: _questionController,
                 maxLines: null,
                 keyboardType: TextInputType.multiline,
                 textCapitalization: TextCapitalization.sentences,
                 decoration: const InputDecoration(
                   labelText: 'Question',
                   hintText: 'Enter the question or prompt...',
                   border: OutlineInputBorder(),
                   alignLabelWithHint: true,
                 ),
                 validator: (value) {
                   if (value == null || value.trim().isEmpty) {
                     return 'Question cannot be empty.';
                   }
                   return null;
                 },
               ),
               const SizedBox(height: 16),
               TextFormField(
                 controller: _answerController,
                 maxLines: null,
                 minLines: 3,
                 keyboardType: TextInputType.multiline,
                 textCapitalization: TextCapitalization.sentences,
                 decoration: const InputDecoration(
                   labelText: 'Answer',
                   hintText: 'Enter the answer...\nSupports Markdown format.\nUse "* " for checklist items.',
                   border: OutlineInputBorder(),
                   alignLabelWithHint: true,
                   helperText: 'Supports Markdown. Use "* " for study checklists.',
                   helperMaxLines: 2,
                 ),
                 validator: (value) {
                   if (value == null || value.trim().isEmpty) {
                     return 'Answer cannot be empty.';
                   }
                   return null;
                 },
               ),
               const SizedBox(height: 24),
             ],
           ),
        ),
      ),
    );
  }
}