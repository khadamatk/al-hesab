import 'package:sqflite/sqflite.dart';

class BalanceReportItem {
  const BalanceReportItem(
    this.accountName,
    this.currencyCode,
    this.balanceMinor,
  );
  final String accountName;
  final String currencyCode;
  final int balanceMinor;
}

class CashFlowReportItem {
  const CashFlowReportItem(
    this.currencyCode,
    this.incomeMinor,
    this.expenseMinor,
  );
  final String currencyCode;
  final int incomeMinor;
  final int expenseMinor;
  int get netMinor => incomeMinor - expenseMinor;
}

class CategoryReportItem {
  const CategoryReportItem(
    this.name,
    this.kind,
    this.currencyCode,
    this.amountMinor,
  );
  final String name;
  final String kind;
  final String currencyCode;
  final int amountMinor;
}

class ObligationReportItem {
  const ObligationReportItem(
    this.currencyCode,
    this.payableMinor,
    this.receivableMinor,
  );
  final String currencyCode;
  final int payableMinor;
  final int receivableMinor;
}

class ReportsSnapshot {
  const ReportsSnapshot({
    required this.balances,
    required this.cashFlow,
    required this.categories,
    required this.obligations,
  });
  final List<BalanceReportItem> balances;
  final List<CashFlowReportItem> cashFlow;
  final List<CategoryReportItem> categories;
  final List<ObligationReportItem> obligations;
}

class ReportsRepository {
  ReportsRepository(this._database);
  final Database _database;

  Future<ReportsSnapshot> load(int workspaceId, String month) async {
    final parts = month.split('-');
    final start = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final end = DateTime(
      start.year,
      start.month + 1,
    ).subtract(const Duration(days: 1));
    return loadRange(workspaceId, _date(start), _date(end));
  }

  Future<ReportsSnapshot> loadRange(
    int workspaceId,
    String from,
    String to,
  ) async {
    final results = await Future.wait([
      _balances(workspaceId),
      _cashFlow(workspaceId, from, to),
      _categories(workspaceId, from, to),
      _obligations(workspaceId),
    ]);
    return ReportsSnapshot(
      balances: results[0] as List<BalanceReportItem>,
      cashFlow: results[1] as List<CashFlowReportItem>,
      categories: results[2] as List<CategoryReportItem>,
      obligations: results[3] as List<ObligationReportItem>,
    );
  }

  Future<List<BalanceReportItem>> _balances(int workspaceId) async {
    final rows = await _database.rawQuery(
      '''
      SELECT a.name account_name, p.currency_code,
        COALESCE(SUM(CASE WHEN t.status = 'posted' THEN e.amount_minor ELSE 0 END), 0) balance
      FROM accounts a JOIN account_pockets p ON p.account_id = a.id
      LEFT JOIN ledger_entries e ON e.pocket_id = p.id
      LEFT JOIN transactions t ON t.id = e.transaction_id
      WHERE a.workspace_id = ? AND a.is_archived = 0 AND p.is_archived = 0
      GROUP BY p.id ORDER BY p.currency_code, a.name COLLATE NOCASE
    ''',
      [workspaceId],
    );
    return rows
        .map(
          (r) => BalanceReportItem(
            r['account_name']! as String,
            r['currency_code']! as String,
            r['balance']! as int,
          ),
        )
        .toList();
  }

  Future<List<CashFlowReportItem>> _cashFlow(
    int workspaceId,
    String from,
    String to,
  ) async {
    final rows = await _database.rawQuery(
      '''
      SELECT p.currency_code,
        COALESCE(SUM(CASE WHEN e.amount_minor > 0 AND
          (t.type = 'income' OR c.kind = 'income') THEN e.amount_minor ELSE 0 END), 0) income,
        COALESCE(SUM(CASE WHEN e.amount_minor < 0 AND
          (t.type = 'expense' OR c.kind = 'expense') THEN -e.amount_minor ELSE 0 END), 0) expense
      FROM transactions t JOIN ledger_entries e ON e.transaction_id = t.id
      JOIN account_pockets p ON p.id = e.pocket_id
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.workspace_id = ? AND t.status = 'posted' AND t.occurred_on BETWEEN ? AND ?
      GROUP BY p.currency_code ORDER BY p.currency_code
    ''',
      [workspaceId, from, to],
    );
    return rows
        .map(
          (r) => CashFlowReportItem(
            r['currency_code']! as String,
            r['income']! as int,
            r['expense']! as int,
          ),
        )
        .toList();
  }

  Future<List<CategoryReportItem>> _categories(
    int workspaceId,
    String from,
    String to,
  ) async {
    final rows = await _database.rawQuery(
      '''
      SELECT name, kind, currency_code, SUM(amount) amount FROM (
        SELECT c.id category_id, c.name, c.kind, p.currency_code,
          ABS(e.amount_minor) amount
        FROM transactions t JOIN categories c ON c.id = t.category_id
        JOIN ledger_entries e ON e.transaction_id = t.id
        JOIN account_pockets p ON p.id = e.pocket_id
        WHERE t.workspace_id = ? AND t.status = 'posted'
          AND t.occurred_on BETWEEN ? AND ?
          AND NOT EXISTS (
            SELECT 1 FROM transaction_splits s WHERE s.transaction_id = t.id
          )
          AND ((c.kind = 'income' AND e.amount_minor > 0) OR
               (c.kind = 'expense' AND e.amount_minor < 0))
        UNION ALL
        SELECT c.id category_id, c.name, c.kind, p.currency_code,
          s.amount_minor amount
        FROM transaction_splits s
        JOIN transactions t ON t.id = s.transaction_id
        JOIN categories c ON c.id = s.category_id
        JOIN ledger_entries e ON e.transaction_id = t.id AND e.amount_minor < 0
        JOIN account_pockets p ON p.id = e.pocket_id
        WHERE t.workspace_id = ? AND t.status = 'posted'
          AND t.occurred_on BETWEEN ? AND ?
      ) grouped
      GROUP BY category_id, currency_code ORDER BY kind, amount DESC
    ''',
      [workspaceId, from, to, workspaceId, from, to],
    );
    return rows
        .map(
          (r) => CategoryReportItem(
            r['name']! as String,
            r['kind']! as String,
            r['currency_code']! as String,
            r['amount']! as int,
          ),
        )
        .toList();
  }

  Future<List<ObligationReportItem>> _obligations(int workspaceId) async {
    final rows = await _database.rawQuery(
      '''
      SELECT o.currency_code,
        COALESCE(SUM(CASE WHEN o.direction = 'payable' THEN
          o.principal_minor - COALESCE((SELECT SUM(p.amount_minor)
            FROM obligation_payments p JOIN transactions t ON t.id = p.transaction_id
            WHERE p.obligation_id = o.id AND t.status = 'posted'), 0) ELSE 0 END), 0) payable,
        COALESCE(SUM(CASE WHEN o.direction = 'receivable' THEN
          o.principal_minor - COALESCE((SELECT SUM(p.amount_minor)
            FROM obligation_payments p JOIN transactions t ON t.id = p.transaction_id
            WHERE p.obligation_id = o.id AND t.status = 'posted'), 0) ELSE 0 END), 0) receivable
      FROM obligations o WHERE o.workspace_id = ? AND o.status != 'cancelled'
      GROUP BY o.currency_code ORDER BY o.currency_code
    ''',
      [workspaceId],
    );
    return rows
        .map(
          (r) => ObligationReportItem(
            r['currency_code']! as String,
            r['payable']! as int,
            r['receivable']! as int,
          ),
        )
        .toList();
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
