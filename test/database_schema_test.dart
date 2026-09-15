import 'dart:io';

import 'package:al_hesab/core/database/app_database.dart';
import 'package:al_hesab/core/database/database_migrations.dart';
import 'package:al_hesab/core/database/schema_v1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase appDatabase;
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    appDatabase = createTestAppDatabase();
    database = await appDatabase.open();
  });

  tearDown(() => appDatabase.close());

  test('creates the complete version-one schema and idempotent seed', () async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll({
        'app_metadata',
        'workspaces',
        'currencies',
        'accounts',
        'account_pockets',
        'categories',
        'counterparties',
        'payment_channels',
        'channel_accounts',
        'transactions',
        'ledger_entries',
        'transaction_fx_details',
        'obligations',
        'obligation_fundings',
        'obligation_payments',
        'budgets',
        'budget_alerts',
        'transaction_splits',
      }),
    );
    expect(await countRows(database, 'currencies'), 3);
    expect(await countRows(database, 'workspaces'), 3);
    expect(await countRows(database, 'categories'), 24);

    await SchemaV1.seed(database, DateTime.utc(2026, 8, 4));
    expect(await countRows(database, 'currencies'), 3);
    expect(await countRows(database, 'workspaces'), 3);
    expect(await countRows(database, 'categories'), 24);
  });

  test(
    'reopens a persisted version-one database without duplicating seed',
    () async {
      final path = p.join(
        Directory.systemTemp.path,
        'al_hesab_reopen_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final persisted = AppDatabase(
        factory: databaseFactoryFfi,
        pathProvider: () async => path,
      );
      try {
        final first = await persisted.open();
        expect(await countRows(first, 'workspaces'), 3);
        await persisted.close();

        final reopened = await persisted.open();
        expect(await countRows(reopened, 'workspaces'), 3);
        expect(await countRows(reopened, 'currencies'), 3);
        expect(await countRows(reopened, 'categories'), 24);
        expect((await reopened.getVersion()), AppDatabase.schemaVersion);
      } finally {
        await persisted.close();
        await databaseFactoryFfi.deleteDatabase(path);
      }
    },
  );

  test('enforces foreign keys and case-insensitive uniqueness', () async {
    final workspace = (await database.query(
      'workspaces',
      where: 'name = ?',
      whereArgs: ['شخصي'],
    )).single;
    final now = DateTime.utc(2026, 8, 4).toIso8601String();

    await expectLater(
      () => database.insert('accounts', {
        'workspace_id': 999999,
        'name': 'بنك',
        'type': 'bank',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await database.insert('accounts', {
      'workspace_id': workspace['id'],
      'name': 'Bank',
      'type': 'bank',
      'created_at': now,
      'updated_at': now,
    });
    await expectLater(
      () => database.insert('accounts', {
        'workspace_id': workspace['id'],
        'name': 'bank',
        'type': 'bank',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('has no mutable balance or floating-point money columns', () async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    for (final table in tables) {
      final name = table['name']! as String;
      final columns = await database.rawQuery('PRAGMA table_info($name)');
      for (final column in columns) {
        final columnName = (column['name']! as String).toLowerCase();
        final type = (column['type']! as String).toUpperCase();
        expect(columnName, isNot(anyOf('balance', 'current_balance')));
        expect(type, isNot(anyOf('REAL', 'DOUBLE', 'FLOAT')));
      }
    }
  });

  test('requires explicit future migrations and rejects downgrades', () async {
    await expectLater(
      DatabaseMigrations.migrate(database, 4, 5),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      DatabaseMigrations.migrate(database, 2, 1),
      throwsA(isA<StateError>()),
    );
  });

  test('version two adds account priority and category hierarchy', () async {
    final accountColumns = await database.rawQuery(
      'PRAGMA table_info(accounts)',
    );
    final categoryColumns = await database.rawQuery(
      'PRAGMA table_info(categories)',
    );
    expect(
      accountColumns.map((e) => e['name']),
      containsAll(['is_favorite', 'sort_order', 'last_used_at']),
    );
    expect(categoryColumns.map((e) => e['name']), contains('parent_id'));
  });

  test(
    'version three adds preferred and recently used currency pockets',
    () async {
      final pocketColumns = await database.rawQuery(
        'PRAGMA table_info(account_pockets)',
      );
      expect(
        pocketColumns.map((e) => e['name']),
        containsAll(['is_default', 'last_used_at']),
      );
    },
  );

  test('version four adds transaction split allocations', () async {
    final columns = await database.rawQuery(
      'PRAGMA table_info(transaction_splits)',
    );
    expect(
      columns.map((e) => e['name']),
      containsAll(['transaction_id', 'category_id', 'amount_minor']),
    );
  });

  test(
    'upgrades a persisted version-one database without losing data',
    () async {
      final path = p.join(
        Directory.systemTemp.path,
        'al_hesab_v1_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => SchemaV1.create(db, DateTime.utc(2026, 8, 4)),
        ),
      );
      final before = await countRows(legacy, 'categories');
      await legacy.close();
      final upgraded = AppDatabase(
        factory: databaseFactoryFfi,
        pathProvider: () async => path,
      );
      try {
        final db = await upgraded.open();
        expect(await db.getVersion(), 4);
        expect(await countRows(db, 'categories'), before);
        expect(
          (await db.query(
            'app_metadata',
            where: 'key = ?',
            whereArgs: ['schema_version'],
          )).single['value'],
          '4',
        );
      } finally {
        await upgraded.close();
        await databaseFactoryFfi.deleteDatabase(path);
      }
    },
  );

  test('enforces general and category budget uniqueness', () async {
    final workspaceId =
        (await database.query(
              'workspaces',
              columns: ['id'],
              where: 'name = ?',
              whereArgs: ['شخصي'],
            )).single['id']!
            as int;
    final categoryId =
        (await database.query(
              'categories',
              columns: ['id'],
              where: 'workspace_id = ? AND kind = ? AND name = ?',
              whereArgs: [workspaceId, 'expense', 'أخرى'],
            )).single['id']!
            as int;
    final now = DateTime.utc(2026, 8, 4).toIso8601String();
    Map<String, Object?> budget(int? category) => {
      'workspace_id': workspaceId,
      'currency_code': 'EGP',
      'category_id': category,
      'monthly_limit_minor': 10000,
      'month': '2026-08',
      'created_at': now,
      'updated_at': now,
    };

    await database.insert('budgets', budget(null));
    await database.insert('budgets', budget(categoryId));
    await expectLater(
      () => database.insert('budgets', budget(null)),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      () => database.insert('budgets', budget(categoryId)),
      throwsA(isA<DatabaseException>()),
    );
  });
}
