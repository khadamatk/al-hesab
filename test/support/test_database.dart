import 'package:al_hesab/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AppDatabase createTestAppDatabase() {
  return AppDatabase(
    factory: databaseFactoryFfi,
    pathProvider: () async => inMemoryDatabasePath,
  );
}

Future<int> countRows(Database database, String table) async {
  final rows = await database.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.single['count']! as int;
}
