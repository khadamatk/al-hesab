import 'package:sqflite/sqflite.dart';

abstract final class DatabaseMigrations {
  static Future<void> migrate(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion > newVersion) {
      throw StateError('Database downgrades are not supported.');
    }
    for (var target = oldVersion + 1; target <= newVersion; target++) {
      await _migrateTo(database, target);
    }
  }

  static Future<void> _migrateTo(Database database, int targetVersion) async {
    return switch (targetVersion) {
      2 => _migrateToVersionTwo(database),
      3 => _migrateToVersionThree(database),
      4 => _migrateToVersionFour(database),
      _ => throw StateError(
        'Missing migration to schema version $targetVersion.',
      ),
    };
  }

  static Future<void> _migrateToVersionTwo(Database database) async {
    await database.execute(
      'ALTER TABLE accounts ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0,1))',
    );
    await database.execute(
      'ALTER TABLE accounts ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
    );
    await database.execute('ALTER TABLE accounts ADD COLUMN last_used_at TEXT');
    await database.execute(
      'ALTER TABLE categories ADD COLUMN parent_id INTEGER REFERENCES categories(id) ON DELETE RESTRICT',
    );
    await database.execute(
      'CREATE INDEX idx_categories_parent ON categories(parent_id)',
    );
    await database.execute('''
      CREATE TRIGGER trg_category_parent_valid_insert
      BEFORE INSERT ON categories WHEN NEW.parent_id IS NOT NULL
      BEGIN
        SELECT CASE WHEN NOT EXISTS (
          SELECT 1 FROM categories p
          WHERE p.id = NEW.parent_id AND p.workspace_id = NEW.workspace_id
            AND p.kind = NEW.kind AND p.parent_id IS NULL
        ) THEN RAISE(ABORT, 'category parent must be a root of the same workspace and kind') END;
      END
    ''');
    await database.execute('''
      CREATE TRIGGER trg_category_parent_valid_update
      BEFORE UPDATE OF parent_id, workspace_id, kind ON categories
      WHEN NEW.parent_id IS NOT NULL
      BEGIN
        SELECT CASE WHEN NEW.parent_id = NEW.id OR NOT EXISTS (
          SELECT 1 FROM categories p
          WHERE p.id = NEW.parent_id AND p.workspace_id = NEW.workspace_id
            AND p.kind = NEW.kind AND p.parent_id IS NULL
        ) THEN RAISE(ABORT, 'category parent must be a root of the same workspace and kind') END;
      END
    ''');
    await database.update(
      'app_metadata',
      {'value': '2'},
      where: 'key = ?',
      whereArgs: ['schema_version'],
    );
  }

  static Future<void> _migrateToVersionThree(Database database) async {
    await database.execute(
      'ALTER TABLE account_pockets ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0,1))',
    );
    await database.execute(
      'ALTER TABLE account_pockets ADD COLUMN last_used_at TEXT',
    );
    await database.execute('''
      CREATE UNIQUE INDEX idx_pockets_one_default_per_account
      ON account_pockets(account_id) WHERE is_default = 1
    ''');
    await database.update(
      'app_metadata',
      {'value': '3'},
      where: 'key = ?',
      whereArgs: ['schema_version'],
    );
  }

  static Future<void> _migrateToVersionFour(Database database) async {
    await database.execute('''
      CREATE TABLE transaction_splits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_transaction_splits_transaction ON transaction_splits(transaction_id)',
    );
    await database.execute(
      'CREATE INDEX idx_transaction_splits_category ON transaction_splits(category_id)',
    );
    await database.update(
      'app_metadata',
      {'value': '4'},
      where: 'key = ?',
      whereArgs: ['schema_version'],
    );
  }
}
