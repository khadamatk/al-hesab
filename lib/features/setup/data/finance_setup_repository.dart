import 'package:sqflite/sqflite.dart';

class WorkspaceItem {
  const WorkspaceItem(this.id, this.name, this.type, this.isArchived);
  final int id;
  final String name;
  final String type;
  final bool isArchived;
}

class CurrencyItem {
  const CurrencyItem(this.code, this.symbol, this.decimalDigits, this.isActive);
  final String code;
  final String symbol;
  final int decimalDigits;
  final bool isActive;
}

class PocketItem {
  const PocketItem(
    this.id,
    this.currencyCode,
    this.balanceMinor,
    this.isDefault,
  );
  final int id;
  final String currencyCode;
  final int balanceMinor;
  final bool isDefault;
}

class AccountItem {
  const AccountItem(
    this.id,
    this.name,
    this.type,
    this.institution,
    this.pockets,
    this.isFavorite,
    this.sortOrder,
  );
  final int id;
  final String name;
  final String type;
  final String? institution;
  final List<PocketItem> pockets;
  final bool isFavorite;
  final int sortOrder;
}

class NamedSetupItem {
  const NamedSetupItem(
    this.id,
    this.name,
    this.type, {
    this.details,
    this.parentId,
    this.parentName,
  });
  final int id;
  final String name;
  final String type;
  final String? details;
  final int? parentId;
  final String? parentName;
  String get displayName => parentName == null ? name : '$parentName › $name';
}

class FinanceSetupRepository {
  FinanceSetupRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Database _database;
  final DateTime Function() _clock;
  String get _timestamp => _clock().toUtc().toIso8601String();

  Future<List<WorkspaceItem>> listWorkspaces() async {
    final rows = await _database.query(
      'workspaces',
      orderBy: 'is_archived, id',
    );
    return rows
        .map(
          (r) => WorkspaceItem(
            r['id']! as int,
            r['name']! as String,
            r['type']! as String,
            r['is_archived'] == 1,
          ),
        )
        .toList();
  }

  Future<int> createWorkspace({
    required String name,
    required String type,
  }) async {
    return _database.transaction((txn) async {
      final id = await txn.insert('workspaces', {
        'name': _requiredText(name, 'name'),
        'type': type,
        'created_at': _timestamp,
        'updated_at': _timestamp,
      });
      for (final category in const [
        ('أخرى', 'expense', 1),
        ('طعام', 'expense', 0),
        ('مواصلات', 'expense', 0),
        ('فواتير', 'expense', 0),
        ('رسوم وعمولات', 'expense', 0),
        ('دخل آخر', 'income', 1),
        ('راتب', 'income', 0),
        ('دخل مشروع', 'income', 0),
      ]) {
        await txn.insert('categories', {
          'workspace_id': id,
          'name': category.$1,
          'kind': category.$2,
          'is_system': category.$3,
          'created_at': _timestamp,
          'updated_at': _timestamp,
        });
      }
      return id;
    });
  }

  Future<void> renameWorkspace(int id, String name) =>
      _rename('workspaces', id, name);
  Future<void> archiveWorkspace(int id, bool value) =>
      _archive('workspaces', id, value);

  Future<List<CurrencyItem>> listCurrencies() async {
    final rows = await _database.query(
      'currencies',
      orderBy: 'is_active DESC, code',
    );
    return rows
        .map(
          (r) => CurrencyItem(
            r['code']! as String,
            r['symbol']! as String,
            r['decimal_digits']! as int,
            r['is_active'] == 1,
          ),
        )
        .toList();
  }

  Future<void> createCurrency({
    required String code,
    required String symbol,
    int decimalDigits = 2,
  }) async {
    await _database.insert('currencies', {
      'code': _requiredText(code, 'code').toUpperCase(),
      'symbol': _requiredText(symbol, 'symbol'),
      'decimal_digits': decimalDigits,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
  }

  Future<void> setCurrencyActive(String code, bool value) => _database.update(
    'currencies',
    {'is_active': value ? 1 : 0, 'updated_at': _timestamp},
    where: 'code = ?',
    whereArgs: [code],
  );

  Future<List<AccountItem>> listAccounts(int workspaceId) async {
    final accounts = await _database.query(
      'accounts',
      where: 'workspace_id = ? AND is_archived = 0',
      whereArgs: [workspaceId],
      orderBy:
          'is_favorite DESC, sort_order, CASE WHEN last_used_at IS NULL THEN 1 ELSE 0 END, last_used_at DESC, name COLLATE NOCASE',
    );
    final result = <AccountItem>[];
    for (final account in accounts) {
      final pockets = await _database.rawQuery(
        '''
        SELECT p.id, p.currency_code, p.is_default, p.last_used_at, COALESCE(SUM(
          CASE WHEN t.status = 'posted' THEN e.amount_minor ELSE 0 END), 0) balance_minor
        FROM account_pockets p
        LEFT JOIN ledger_entries e ON e.pocket_id = p.id
        LEFT JOIN transactions t ON t.id = e.transaction_id
        WHERE p.account_id = ? AND p.is_archived = 0
        GROUP BY p.id
        ORDER BY p.is_default DESC,
          CASE WHEN p.last_used_at IS NULL THEN 1 ELSE 0 END,
          p.last_used_at DESC, p.currency_code
      ''',
        [account['id']],
      );
      result.add(
        AccountItem(
          account['id']! as int,
          account['name']! as String,
          account['type']! as String,
          account['institution'] as String?,
          pockets
              .map(
                (p) => PocketItem(
                  p['id']! as int,
                  p['currency_code']! as String,
                  p['balance_minor']! as int,
                  p['is_default'] == 1,
                ),
              )
              .toList(),
          account['is_favorite'] == 1,
          account['sort_order']! as int,
        ),
      );
    }
    return result;
  }

  Future<int> createAccount({
    required int workspaceId,
    required String name,
    required String type,
    String? institution,
    String? identifierHint,
    bool allowNegative = false,
  }) => _database.insert('accounts', {
    'workspace_id': workspaceId,
    'name': _requiredText(name, 'name'),
    'type': type,
    'institution': _optionalText(institution),
    'identifier_hint': _optionalText(identifierHint),
    'allow_negative': allowNegative ? 1 : 0,
    'created_at': _timestamp,
    'updated_at': _timestamp,
  });

  Future<int> createPocket({
    required int accountId,
    required String currencyCode,
  }) => _database.transaction((txn) async {
    final existing =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) FROM account_pockets WHERE account_id = ? AND is_archived = 0',
            [accountId],
          ),
        ) ??
        0;
    return txn.insert('account_pockets', {
      'account_id': accountId,
      'currency_code': currencyCode.toUpperCase(),
      'is_default': existing == 0 ? 1 : 0,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
  });
  Future<void> renameAccount(int id, String name) =>
      _rename('accounts', id, name);
  Future<void> archiveAccount(int id) => _archive('accounts', id, true);
  Future<void> setAccountFavorite(int id, bool value) => _database.update(
    'accounts',
    {'is_favorite': value ? 1 : 0, 'updated_at': _timestamp},
    where: 'id = ?',
    whereArgs: [id],
  );
  Future<void> setDefaultPocket(int pocketId) async {
    await _database.transaction((txn) async {
      final pocket = await txn.query(
        'account_pockets',
        columns: ['account_id'],
        where: 'id = ? AND is_archived = 0',
        whereArgs: [pocketId],
        limit: 1,
      );
      if (pocket.isEmpty) throw StateError('Pocket not found');
      final accountId = pocket.single['account_id']! as int;
      await txn.update(
        'account_pockets',
        {'is_default': 0, 'updated_at': _timestamp},
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
      await txn.update(
        'account_pockets',
        {'is_default': 1, 'updated_at': _timestamp},
        where: 'id = ?',
        whereArgs: [pocketId],
      );
    });
  }

  Future<void> moveAccount(int id, int sortOrder) => _database.update(
    'accounts',
    {'sort_order': sortOrder, 'updated_at': _timestamp},
    where: 'id = ?',
    whereArgs: [id],
  );
  Future<void> markAccountUsedByPocket(int pocketId) async {
    await _database.transaction((txn) async {
      await txn.rawUpdate(
        '''UPDATE accounts SET last_used_at = ?, updated_at = ?
           WHERE id = (SELECT account_id FROM account_pockets WHERE id = ?)''',
        [_timestamp, _timestamp, pocketId],
      );
      await txn.update(
        'account_pockets',
        {'last_used_at': _timestamp, 'updated_at': _timestamp},
        where: 'id = ?',
        whereArgs: [pocketId],
      );
    });
  }

  Future<List<NamedSetupItem>> listCategories(int workspaceId) async {
    final rows = await _database.rawQuery(
      '''
      SELECT c.id, c.name, c.kind, c.parent_id, p.name parent_name
      FROM categories c LEFT JOIN categories p ON p.id = c.parent_id
      WHERE c.workspace_id = ? AND c.is_archived = 0
      ORDER BY c.kind, COALESCE(p.name, c.name) COLLATE NOCASE,
        c.parent_id IS NOT NULL, c.name COLLATE NOCASE
    ''',
      [workspaceId],
    );
    return rows
        .map(
          (r) => NamedSetupItem(
            r['id']! as int,
            r['name']! as String,
            r['kind']! as String,
            parentId: r['parent_id'] as int?,
            parentName: r['parent_name'] as String?,
          ),
        )
        .toList();
  }

  Future<int> createCategory({
    required int workspaceId,
    required String name,
    required String kind,
    int? parentId,
  }) => _database.insert('categories', {
    'workspace_id': workspaceId,
    'name': _requiredText(name, 'name'),
    'kind': kind,
    'parent_id': parentId,
    'created_at': _timestamp,
    'updated_at': _timestamp,
  });
  Future<void> updateCategory({
    required int id,
    required String name,
    int? parentId,
  }) => _database.update(
    'categories',
    {
      'name': _requiredText(name, 'name'),
      'parent_id': parentId,
      'updated_at': _timestamp,
    },
    where: 'id = ?',
    whereArgs: [id],
  );
  Future<void> renameCategory(int id, String name) =>
      _rename('categories', id, name);
  Future<void> archiveCategory(int id) => _archive('categories', id, true);

  Future<List<NamedSetupItem>> listCounterparties(int workspaceId) async =>
      _listNamed('counterparties', workspaceId);
  Future<int> createCounterparty({
    required int workspaceId,
    required String name,
    required String type,
  }) => _createNamed('counterparties', workspaceId, name, 'type', type);
  Future<void> renameCounterparty(int id, String name) =>
      _rename('counterparties', id, name);
  Future<void> archiveCounterparty(int id) =>
      _archive('counterparties', id, true);

  Future<List<NamedSetupItem>> listChannels(int workspaceId) async {
    final rows = await _database.rawQuery(
      '''
      SELECT c.id, c.name, c.type, GROUP_CONCAT(a.name, '، ') details
      FROM payment_channels c
      LEFT JOIN channel_accounts ca ON ca.channel_id = c.id
      LEFT JOIN accounts a ON a.id = ca.account_id
      WHERE c.workspace_id = ? AND c.is_archived = 0
      GROUP BY c.id ORDER BY c.name COLLATE NOCASE
    ''',
      [workspaceId],
    );
    return rows
        .map(
          (r) => NamedSetupItem(
            r['id']! as int,
            r['name']! as String,
            r['type']! as String,
            details: r['details'] as String?,
          ),
        )
        .toList();
  }

  Future<int> createChannel({
    required int workspaceId,
    required String name,
    required String type,
  }) => _createNamed('payment_channels', workspaceId, name, 'type', type);
  Future<void> linkChannelToAccount({
    required int channelId,
    required int accountId,
  }) async {
    await _database.insert('channel_accounts', {
      'channel_id': channelId,
      'account_id': accountId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> archiveChannel(int id) => _archive('payment_channels', id, true);

  Future<List<NamedSetupItem>> _listNamed(String table, int workspaceId) async {
    final kindColumn = table == 'categories' ? 'kind' : 'type';
    final rows = await _database.query(
      table,
      where: 'workspace_id = ? AND is_archived = 0',
      whereArgs: [workspaceId],
      orderBy: '$kindColumn, name COLLATE NOCASE',
    );
    return rows
        .map(
          (r) => NamedSetupItem(
            r['id']! as int,
            r['name']! as String,
            r[kindColumn]! as String,
          ),
        )
        .toList();
  }

  Future<int> _createNamed(
    String table,
    int workspaceId,
    String name,
    String typeColumn,
    String type,
  ) => _database.insert(table, {
    'workspace_id': workspaceId,
    'name': _requiredText(name, 'name'),
    typeColumn: type,
    'created_at': _timestamp,
    'updated_at': _timestamp,
  });
  Future<void> _rename(String table, int id, String name) => _database.update(
    table,
    {'name': _requiredText(name, 'name'), 'updated_at': _timestamp},
    where: 'id = ?',
    whereArgs: [id],
  );
  Future<void> _archive(String table, int id, bool value) => _database.update(
    table,
    {'is_archived': value ? 1 : 0, 'updated_at': _timestamp},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<int> workspaceId(String name) async {
    final rows = await _database.query(
      'workspaces',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Workspace not found: $name');
    return rows.single['id']! as int;
  }

  Future<int> categoryId({
    required int workspaceId,
    required String name,
    required String kind,
  }) async {
    final rows = await _database.query(
      'categories',
      columns: ['id'],
      where: 'workspace_id = ? AND kind = ? AND name = ? COLLATE NOCASE',
      whereArgs: [workspaceId, kind, name],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Category not found: $name');
    return rows.single['id']! as int;
  }

  static String _requiredText(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(value, field, 'Required');
    return trimmed;
  }

  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
