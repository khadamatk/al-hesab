import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final databaseReadyProvider = FutureProvider<bool>((ref) async {
  final database = await ref.watch(appDatabaseProvider).open();
  final rows = await database.query(
    'app_metadata',
    where: 'key = ?',
    whereArgs: ['schema_initialized'],
    limit: 1,
  );
  return rows.singleOrNull?['value'] == 'true';
});
