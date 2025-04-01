// lib/providers/service_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your service classes
import '../services/persistence_service.dart';
import '../services/database_helper.dart';

// Provider for SharedPreferences (asynchronously loads the instance)
// This is useful if other services might also need SharedPreferences later.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

// Provider for PersistenceService
// It depends on sharedPreferencesProvider to get the SharedPreferences instance.
// We use FutureProvider because SharedPreferences loading is async.
final persistenceServiceProvider = FutureProvider<PersistenceService>((ref) async {
  // Wait for SharedPreferences to be ready
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  // Create PersistenceService with the instance
  return PersistenceService(prefs);
  // Note: We don't need PersistenceService.create() here because
  // we are manually getting the dependency (prefs) via another provider.
});

// Provider for DatabaseHelper
// It depends on persistenceServiceProvider to get the PersistenceService instance.
// We use FutureProvider because PersistenceService creation might depend on async SharedPreferences.
final databaseHelperProvider = FutureProvider<DatabaseHelper>((ref) async {
  // Wait for PersistenceService to be ready
  final persistenceService = await ref.watch(persistenceServiceProvider.future);
  // Create DatabaseHelper with the instance
  return DatabaseHelper(persistenceService);
  // Note: We don't need DatabaseHelper.create() here because
  // we are manually getting the dependency (persistenceService) via another provider.
});

// If you prefer simpler providers *assuming* the instances will be ready
// when needed (use with caution, especially during app startup), you could use:
/*
final simplisticPersistenceProvider = Provider<PersistenceService>((ref) {
  // This would throw if SharedPreferences wasn't ready yet. Not recommended.
  final prefs = ref.watch(sharedPreferencesProvider).value!;
  return PersistenceService(prefs);
});

final simplisticDatabaseHelperProvider = Provider<DatabaseHelper>((ref) {
  // This would throw if PersistenceService wasn't ready. Not recommended.
  final persistenceService = ref.watch(persistenceServiceProvider).value!;
  return DatabaseHelper(persistenceService);
});
*/