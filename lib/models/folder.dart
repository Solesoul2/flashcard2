// lib/models/folder.dart
import 'package:flutter/foundation.dart'; // Required for ValueGetter used in copyWith

// Represents an immutable folder which can contain flashcards or other subfolders.
@immutable // Indicates the class and its subclasses should be immutable.
class Folder {
  final int? id; // Unique identifier from the database; null if not yet saved.
  final String name; // Name of the folder displayed to the user.
  final int? parentId; // ID of the parent folder; null for root folders.

  // Constructor with required name and optional id/parentId.
  const Folder({
    this.id,
    required this.name,
    this.parentId,
  });

  // Converts a Folder object into a Map for database operations.
  // Keys correspond to column names in the 'folders' table.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parentId': parentId,
    };
  }

  // Creates a Folder object from a Map (e.g., from the database).
  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      // Ensure correct type casting and handle potential nulls from DB.
      id: map['id'] as int?,
      name: map['name'] as String? ?? 'Unnamed Folder', // Default name if null
      parentId: map['parentId'] as int?,
    );
  }

  // Creates a copy of this Folder instance with potentially updated fields.
  Folder copyWith({
    int? id,
    String? name,
    // Use ValueGetter to distinguish between setting parentId to null and not changing it
    ValueGetter<int?>? parentId,
  }) {
    return Folder(
      // If a new value is provided, use it; otherwise, keep the existing value.
      id: id ?? this.id,
      name: name ?? this.name,
      // If parentId getter is provided, call it to get the new value (which could be null).
      // Otherwise, keep the existing parentId.
      parentId: parentId != null ? parentId() : this.parentId,
    );
  }

  // Override toString for better debug output.
  @override
  String toString() {
    return 'Folder(id: $id, name: "$name", parentId: $parentId)';
  }

  // Override equality operator (==) for comparing Folder instances.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Folder &&
      other.id == id &&
      other.name == name &&
      other.parentId == parentId;
  }

  // Override hashCode to be consistent with the == operator.
  @override
  int get hashCode {
    return id.hashCode ^ name.hashCode ^ parentId.hashCode;
  }
}