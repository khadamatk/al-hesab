import 'package:sqflite/sqflite.dart';

class BudgetItem {
  const BudgetItem({
    required this.id,
    required this.currencyCode,
    required this.month,
    required this.limitMinor,
    required this.thresholdPercent,
    required this.spentMinor,
    this.categoryId,
    this.categoryName,
    required this.triggeredLevels,
  });
  final int id;
  final String currencyCode;
  final String month;
  final int limitMinor;
  final int thresholdPercent;
  final int spentMinor;
  final int? categoryId;
  final String? categoryName;
  final Set<String> triggeredLevels;
  double get progress => limitMinor == 0 ? 0 : spentMinor / limitMinor;
}

class BudgetRepository {
  BudgetRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final Database _database;
  final DateTime Function() _clock;
  String get _timestamp => _clock().toUtc().toIso8601String();

  Future<int> create({
    required int workspaceId,
    required String currencyCode,
    required int limitMinor,
    required String month,
    int? categoryId,
    int thresholdPercent = 80,
  }) async {
    if (limitMinor <= 0) throw ArgumentError('Budget limit must be positive.');
    return _database.insert('budgets', {
      'workspace_id': workspaceId,
      'currency_code': currencyCode.toUpperCase(),
      'category_id': categoryId,
      'monthly_limit_minor': limitMinor,
      'alert_threshold_percent': thresholdPercent,
      'month': month,
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
  }

  Future<void> updateLimit(int id, int limitMinor) async {
    if (limitMinor <= 0) throw ArgumentError('Budget limit must be positive.');
    await _database.update(
      'budgets',
      {'monthly_limit_minor': limitMinor, 'updated_at': _timestamp},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) =>
      _database.delete('budgets', where: 'id = ?', whereArgs: [id]);

  Future<List<BudgetItem>> list(int workspaceId, String month) async {
    final budgets = await _database.rawQuery(
      '''
      SELECT b.*, c.name category_name FROM budgets b
      LEFT JOIN categories c ON c.id = b.category_id
      WHERE b.workspace_id = ? AND b.month = ?
      ORDER BY b.currency_code, b.category_id IS NOT NULL, c.name
    ''',
      [workspaceId, month],
    );
    final result = <BudgetItem>[];
    for (final budget in budgets) {
      final spent = await _spent(budget);
      await _syncAlerts(
        budget['id']! as int,
        spent,
        budget['monthly_limit_minor']! as int,
        budget['alert_threshold_percent']! as int,
      );
      final alerts = await _database.query(
        'budget_alerts',
        columns: ['level'],
        where: 'budget_id = ?',
        whereArgs: [budget['id']],
      );
      result.add(
        BudgetItem(
          id: budget['id']! as int,
          currencyCode: budget['currency_code']! as String,
          month: budget['month']! as String,
          limitMinor: budget['monthly_limit_minor']! as int,
          thresholdPercent: budget['alert_threshold_percent']! as int,
          spentMinor: spent,
          categoryId: budget['category_id'] as int?,
          categoryName: budget['category_name'] as String?,
          triggeredLevels: alerts.map((e) => e['level']! as String).toSet(),
        ),
      );
    }
    return result;
  }

  Future<int> _spent(Map<String, Object?> budget) async {
    final categoryId = budget['category_id'] as int?;
    if (categoryId != null) {
      final rows = await _database.rawQuery(
        '''
        SELECT COALESCE(SUM(amount), 0) spent FROM (
          SELECT -e.amount_minor amount
          FROM ledger_entries e JOIN transactions t ON t.id = e.transaction_id
          JOIN account_pockets p ON p.id = e.pocket_id
          WHERE t.workspace_id = ? AND t.status = 'posted'
            AND substr(t.occurred_on, 1, 7) = ?
            AND p.currency_code = ? COLLATE NOCASE
            AND e.amount_minor < 0 AND t.category_id = ?
            AND NOT EXISTS (
              SELECT 1 FROM transaction_splits s WHERE s.transaction_id = t.id
            )
          UNION ALL
          SELECT s.amount_minor amount
          FROM transaction_splits s JOIN transactions t ON t.id = s.transaction_id
          JOIN ledger_entries e ON e.transaction_id = t.id AND e.amount_minor < 0
          JOIN account_pockets p ON p.id = e.pocket_id
          WHERE t.workspace_id = ? AND t.status = 'posted'
            AND substr(t.occurred_on, 1, 7) = ?
            AND p.currency_code = ? COLLATE NOCASE AND s.category_id = ?
        )
      ''',
        [
          budget['workspace_id'],
          budget['month'],
          budget['currency_code'],
          categoryId,
          budget['workspace_id'],
          budget['month'],
          budget['currency_code'],
          categoryId,
        ],
      );
      return rows.single['spent']! as int;
    }
    final rows = await _database.rawQuery(
      '''
      SELECT COALESCE(SUM(-e.amount_minor), 0) spent
      FROM ledger_entries e
      JOIN transactions t ON t.id = e.transaction_id
      JOIN account_pockets p ON p.id = e.pocket_id
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.workspace_id = ? AND t.status = 'posted'
        AND substr(t.occurred_on, 1, 7) = ? AND p.currency_code = ? COLLATE NOCASE
        AND e.amount_minor < 0 AND (t.type = 'expense' OR c.kind = 'expense')
        AND t.type = 'expense'
    ''',
      [budget['workspace_id'], budget['month'], budget['currency_code']],
    );
    return rows.single['spent']! as int;
  }

  Future<void> _syncAlerts(
    int budgetId,
    int spent,
    int limit,
    int threshold,
  ) async {
    final percent = spent * 100 / limit;
    if (percent >= threshold) await _insertAlert(budgetId, 'threshold');
    if (percent >= 100) await _insertAlert(budgetId, 'exceeded');
  }

  Future<void> _insertAlert(int budgetId, String level) async {
    await _database.insert('budget_alerts', {
      'budget_id': budgetId,
      'level': level,
      'triggered_at': _timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
