// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/folder_page.dart'; // Entry point screen

void main() {
  // Ensure Flutter bindings are initialized before running the app.
  WidgetsFlutterBinding.ensureInitialized();
  // Wrap the entire app in a ProviderScope for Riverpod state management.
  runApp(const ProviderScope(child: FlashcardApp()));
}

class FlashcardApp extends StatelessWidget {
  const FlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Define a single seed color for the theme.
    const Color seedColor = Colors.pink;

    // Generate the ColorScheme ONCE from the seed color.
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      // brightness: Brightness.light, // Keep light mode default
    );

    return MaterialApp(
      title: 'Flashcard App',
      // Enable Material 3 and define the theme using the generated ColorScheme.
      theme: ThemeData(
        // Apply the generated color scheme.
        colorScheme: colorScheme,
        // Enable Material 3 design features.
        useMaterial3: true,
        // Use the generated scheme for component themes.

        // Consistent Card styling.
        cardTheme: CardTheme(
          elevation: 1, // M3 default is often lower elevation.
          margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          // Card color defaults to colorScheme.surface in M3 - no need to set explicitly unless overriding.
        ),

        // Consistent ListTile styling.
        listTileTheme: ListTileThemeData(
           selectedTileColor: colorScheme.primaryContainer.withOpacity(0.3), // Use scheme color for selection.
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
           iconColor: colorScheme.onSurfaceVariant, // Use scheme color for icons.
           // textColor: colorScheme.onSurface, // Default M3 text colors usually work well.
           // dense: true, // Consider if default density is okay or if compactness is needed everywhere.
           // visualDensity: VisualDensity.compact,
        ),

        // Consistent Checkbox styling.
        checkboxTheme: CheckboxThemeData(
           // fillColor uses colorScheme.primary when selected by default in M3.
           // Check color defaults based on fill color contrast (often white on primary).
           // Override only if defaults are not suitable.
           /* Example override:
           fillColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) {
                return colorScheme.primary; // Explicitly use scheme primary
              }
              return null; // Use default otherwise
           }),
           checkColor: MaterialStateProperty.all(colorScheme.onPrimary), // Explicit white check on primary
           */
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
        ),

        // Consistent Dialog styling.
        dialogTheme: DialogTheme(
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), // Slightly larger radius common in M3
           // M3 defaults usually derive title/content styles from textTheme.
           // titleTextStyle: TextStyle(color: colorScheme.onSurface), // Override if needed
        ),

        // Define AppBar theme for consistency.
        appBarTheme: AppBarTheme(
          // M3 AppBar defaults usually use colorScheme.surface or surfaceContainer.
          backgroundColor: colorScheme.surface, // Explicitly set if needed
          foregroundColor: colorScheme.onSurface, // Text/icon color
          elevation: 0, // M3 often uses 0 elevation.
          scrolledUnderElevation: 2, // Elevation when content scrolls under.
          centerTitle: false, // Default is usually false, good practice.
        ),

         // Define FloatingActionButton theme.
         floatingActionButtonTheme: FloatingActionButtonThemeData(
            // Defaults derive from colorScheme.primaryContainer/onPrimaryContainer generally.
             backgroundColor: colorScheme.primaryContainer,
             foregroundColor: colorScheme.onPrimaryContainer,
             // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), // M3 FAB shape
         ),

         // Define ElevatedButton theme using the scheme.
         elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
               backgroundColor: colorScheme.primary,
               foregroundColor: colorScheme.onPrimary,
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Consistent radius
               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), // Adjusted padding
            ),
         ),

         // Define TextButton theme (useful for dialog actions).
         textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
               foregroundColor: colorScheme.primary, // Use primary color for text.
               // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Consistent radius
            ),
         ),

         // Input decoration theme for TextFormFields.
         inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder( // Default border style
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder( // Border when focused
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: colorScheme.primary, width: 2.0),
            ),
            enabledBorder: OutlineInputBorder( // Border when enabled but not focused
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: colorScheme.outline),
            ),
            // Consider filled style for better visual separation if desired.
            filled: true,
            fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
            // labelStyle: TextStyle(color: colorScheme.onSurfaceVariant), // Style for label when floating
            // hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
         ),

         // Define default text styles if needed for more consistency.
         // textTheme: // M3 text themes are usually well-defined, customize if needed.

      ),
      // Set the initial screen of the app.
      home: const FolderPage(), // Start with the root folder page
      // Hide the debug banner in the top-right corner.
      debugShowCheckedModeBanner: false,
    );
  }
}