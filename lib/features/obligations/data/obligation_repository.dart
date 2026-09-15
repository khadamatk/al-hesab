import 'package:sqflite/sqflite.dart';

import '../../ledger/data/ledger_repository.dart';

class ObligationItem {
  const ObligationItem({
    required this.id,
    required this.counterpartyName,
    required this.direction,
    required this.nature,
    required this.currencyCode,
    required this.principalMinor,
    required this.remainingMinor,
    required this.fundedMinor,
    required this.status,
  });
  final int id;
  final String counterpartyName;
  final String direction;
  final String nature;
  final String currencyCode;
  final int principalMinor;
  final int remainingMinor;
  final int fundedMinor;
  final String status;
}

class ObligationRepository {
  ObligationRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Database _database;
  final DateTime Function() _clock;

  String get _timestamp => _clock().toUtc().toIso8601String();

  Future<List<ObligationItem>> list(int workspaceId) async {
    final rows = await _database.rawQuery(
      '''
      SELECT o.id, c.name counterparty_name, o.direction, o.nature,
        o.currency_code, o.principal_minor, o.status,
        o.principal_minor - COALESCE((SELECT SUM(p.amount_minor)
          FROM obligation_payments p JOIN transactions pt ON pt.id = p.transaction_id
          WHERE p.obligation_id = o.id AND pt.status = 'posted'), 0) remaining_minor,
        COALESCE((SELECT SUM(f.amount_minor)
          FROM obligation_fundings f JOIN transactions ft ON ft.id = f.transaction_id
          WHERE f.obligation_id = o.id AND ft.status = 'posted'), 0) funded_minor
      FROM obligations o
      JOIN counterparties c ON c.id = o.counterparty_id
      LEFT JOIN obligation_payments p ON p.obligation_id = o.id
      LEFT JOIN transactions t ON t.id = p.transaction_id
      WHERE o.workspace_id = ? AND o.status != 'cancelled'
      GROUP BY o.id ORDER BY CASE o.status WHEN 'settled' THEN 1 ELSE 0 END, o.id DESC
    ''',
      [workspaceId],
    );
    return rows
        .map(
          (r) => ObligationItem(
            id: r['id']! as int,
            counterpartyName: r['counterparty_name']! as String,
            direction: r['direction']! as String,
            nature: r['nature']! as String,
            currencyCode: r['currency_code']! as String,
            principalMinor: r['principal_minor']! as int,
            remainingMinor: r['remaining_minor']! as int,
            fundedMinor: r['funded_minor']! as int,
            status: r['status']! as String,
          ),
        )
        .toList();
  }

  Future<int> create({
    required int workspaceId,
    required int counterpartyId,
    required String direction,
    required String nature,
    required String currencyCode,
    required int principalMinor,
    required String openedOn,
    int? categoryId,
    String? dueOn,
    String? note,
  }) {
    if (principalMinor <= 0) {
      throw ArgumentError('Principal must be positive.');
    }
    return _database.insert('obligations', {
      'workspace_id': workspaceId,
      'counterparty_id': counterpartyId,
      'direction': direction,
      'nature': nature,
      'currency_code': currencyCode.toUpperCase(),
      'category_id': categoryId,
      'principal_minor': principalMinor,
      'opened_on': openedOn,
      'due_on': dueOn,
      'note': note?.trim(),
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
  }

  Future<int> settle({
    required int obligationId,
    required int pocketId,
    required int obligationAmountMinor,
    required int pocketAmountMinor,
    required String occurredOn,
    int? channelId,
    FxSettlement? fxSettlement,
    String? note,
  }) async {
    if (obligationAmountMinor <= 0 || pocketAmountMinor <= 0) {
      throw ArgumentError('Settlement amounts must be positive.');
    }
    return _database.transaction((txn) async {
      final obligation = await _obligation(txn, obligationId);
      final pocket = await _pocket(txn, pocketId);
      if (obligation.workspaceId != pocket.workspaceId) {
        throw StateError('Obligation and pocket must share a workspace.');
      }
      final sameCurrency =
          obligation.currencyCode.toUpperCase() ==
          pocket.currencyCode.toUpperCase();
      if (sameCurrency && obligationAmountMinor != pocketAmountMinor) {
        throw ArgumentError('Same-currency settlement amounts must match.');
      }
      if (!sameCurrency && fxSettlement == null) {
        throw ArgumentError('Cross-currency settlement requires FX details.');
      }
      if (!sameCurrency) {
        if (obligation.direction == 'payable') {
          _validateFx(
            fxSettlement!,
            sourceCurrency: pocket.currencyCode,
            sourceAmount: pocketAmountMinor,
            destinationCurrency: obligation.currencyCode,
            destinationAmount: obligationAmountMinor,
          );
        } else {
          _validateFx(
            fxSettlement!,
            sourceCurrency: obligation.currencyCode,
            sourceAmount: obligationAmountMinor,
            destinationCurrency: pocket.currencyCode,
            destinationAmount: pocketAmountMinor,
          );
        }
      }

      final paid = await _paidAmount(txn, obligationId);
      if (paid + obligationAmountMinor > obligation.principalMinor) {
        throw StateError('Payment exceeds obligation remainder.');
      }
      if (obligation.direction == 'payable' && !pocket.allowNegative) {
        final balance = await _balance(txn, pocketId);
        if (balance < pocketAmountMinor) {
          throw StateError('Insufficient pocket balance.');
        }
      }

      final transactionId = await txn.insert('transactions', {
        'workspace_id': obligation.workspaceId,
        'type': 'obligation_settlement',
        'category_id': obligation.categoryId,
        'counterparty_id': obligation.counterpartyId,
        'channel_id': channelId,
        'occurred_on': occurredOn,
        'note': note?.trim(),
        'created_at': _timestamp,
        'updated_at': _timestamp,
      });
      await txn.insert('ledger_entries', {
        'transaction_id': transactionId,
        'pocket_id': pocketId,
        'role': 'single',
        'amount_minor': obligation.direction == 'payable'
            ? -pocketAmountMinor
            : pocketAmountMinor,
        'created_at': _timestamp,
      });
      if (fxSettlement != null) {
        await txn.insert('transaction_fx_details', {
          'transaction_id': transactionId,
          'source_currency_code': fxSettlement.sourceCurrencyCode.toUpperCase(),
          'source_amount_minor': fxSettlement.sourceAmountMinor,
          'destination_currency_code': fxSettlement.destinationCurrencyCode
              .toUpperCase(),
          'destination_amount_minor': fxSettlement.destinationAmountMinor,
          'created_at': _timestamp,
        });
      }
      await txn.insert('obligation_payments', {
        'obligation_id': obligationId,
        'transaction_id': transactionId,
        'amount_minor': obligationAmountMinor,
        'created_at': _timestamp,
      });

      final newPaid = paid + obligationAmountMinor;
      await txn.update(
        'obligations',
        {
          'status': newPaid == obligation.principalMinor
              ? 'settled'
              : 'partial',
          'updated_at': _timestamp,
        },
        where: 'id = ?',
        whereArgs: [obligationId],
      );
      return transactionId;
    });
  }

  Future<int> remaining(int obligationId) async {
    final rows = await _database.rawQuery(
      '''
        SELECT o.principal_minor - COALESCE(SUM(
          CASE WHEN t.status = 'posted' THEN p.amount_minor ELSE 0 END
        ), 0) AS remaining
        FROM obligations o
        LEFT JOIN obligation_payments p ON p.obligation_id = o.id
        LEFT JOIN transactions t ON t.id = p.transaction_id
        WHERE o.id = ?
        GROUP BY o.id
      ''',
      [obligationId],
    );
    if (rows.isEmpty) throw StateError('Obligation not found.');
    return rows.single['remaining']! as int;
  }

  Future<int> fund({
    required int obligationId,
    required int pocketId,
    required int obligationAmountMinor,
    required int pocketAmountMinor,
    required String occurredOn,
    int? channelId,
    FxSettlement? fxSettlement,
    String? note,
  }) async {
    if (obligationAmountMinor <= 0 || pocketAmountMinor <= 0) {
      throw ArgumentError('Funding amounts must be positive.');
    }
    return _database.transaction((txn) async {
      final obligation = await _obligation(txn, obligationId);
      if (obligation.nature != 'loan' && obligation.nature != 'money_lent') {
        throw StateError('Only loans and money lent have funding movements.');
      }
      final pocket = await _pocket(txn, pocketId);
      if (obligation.workspaceId != pocket.workspaceId) {
        throw StateError('Obligation and pocket must share a workspace.');
      }
      final sameCurrency =
          obligation.currencyCode.toUpperCase() ==
          pocket.currencyCode.toUpperCase();
      if (sameCurrency && obligationAmountMinor != pocketAmountMinor) {
        throw ArgumentError('Same-currency funding amounts must match.');
      }
      if (!sameCurrency && fxSettlement == null) {
        throw ArgumentError('Cross-currency funding requires FX details.');
      }
      if (!sameCurrency) {
        if (obligation.nature == 'loan') {
          _validateFx(
            fxSettlement!,
            sourceCurrency: obligation.currencyCode,
            sourceAmount: obligationAmountMinor,
            destinationCurrency: pocket.currencyCode,
            destinationAmount: pocketAmountMinor,
          );
        } else {
          _validateFx(
            fxSettlement!,
            sourceCurrency: pocket.currencyCode,
            sourceAmount: pocketAmountMinor,
            destinationCurrency: obligation.currencyCode,
            destinationAmount: obligationAmountMinor,
          );
        }
      }
      final funded = await _fundedAmount(txn, obligationId);
      if (funded + obligationAmountMinor > obligation.principalMinor) {
        throw StateError('Funding exceeds obligation principal.');
      }
      if (obligation.nature == 'money_lent' && !pocket.allowNegative) {
        final balance = await _balance(txn, pocketId);
        if (balance < pocketAmountMinor) {
          throw StateError('Insufficient pocket balance.');
        }
      }

      final transactionId = await txn.insert('transactions', {
        'workspace_id': obligation.workspaceId,
        'type': 'obligation_funding',
        'counterparty_id': obligation.counterpartyId,
        'channel_id': channelId,
        'occurred_on': occurredOn,
        'note': note?.trim(),
        'created_at': _timestamp,
        'updated_at': _timestamp,
      });
      await txn.insert('ledger_entries', {
        'transaction_id': transactionId,
        'pocket_id': pocketId,
        'role': 'single',
        'amount_minor': obligation.nature == 'loan'
            ? pocketAmountMinor
            : -pocketAmountMinor,
        'created_at': _timestamp,
      });
      if (fxSettlement != null) {
        await txn.insert('transaction_fx_details', {
          'transaction_id': transactionId,
          'source_currency_code': fxSettlement.sourceCurrencyCode.toUpperCase(),
          'source_amount_minor': fxSettlement.sourceAmountMinor,
          'destination_currency_code': fxSettlement.destinationCurrencyCode
              .toUpperCase(),
          'destination_amount_minor': fxSettlement.destinationAmountMinor,
          'created_at': _timestamp,
        });
      }
      await txn.insert('obligation_fundings', {
        'obligation_id': obligationId,
        'transaction_id': transactionId,
        'amount_minor': obligationAmountMinor,
        'created_at': _timestamp,
      });
      return transactionId;
    });
  }

  Future<_Obligation> _obligation(
    DatabaseExecutor txn,
    int obligationId,
  ) async {
    final rows = await txn.query(
      'obligations',
      where: 'id = ? AND status != ?',
      whereArgs: [obligationId, 'cancelled'],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Open obligation not found.');
    final row = rows.single;
    return _Obligation(
      workspaceId: row['workspace_id']! as int,
      counterpartyId: row['counterparty_id']! as int,
      categoryId: row['category_id'] as int?,
      direction: row['direction']! as String,
      nature: row['nature']! as String,
      currencyCode: row['currency_code']! as String,
      principalMinor: row['principal_minor']! as int,
    );
  }

  Future<_Pocket> _pocket(DatabaseExecutor txn, int pocketId) async {
    final rows = await txn.rawQuery(
      '''
        SELECT p.currency_code, a.workspace_id, a.allow_negative
        FROM account_pockets p
        JOIN accounts a ON a.id = p.account_id
        WHERE p.id = ? AND p.is_archived = 0 AND a.is_archived = 0
      ''',
      [pocketId],
    );
    if (rows.isEmpty) throw StateError('Active pocket not found.');
    final row = rows.single;
    return _Pocket(
      workspaceId: row['workspace_id']! as int,
      currencyCode: row['currency_code']! as String,
      allowNegative: row['allow_negative'] == 1,
    );
  }

  Future<int> _paidAmount(DatabaseExecutor txn, int obligationId) async {
    final rows = await txn.rawQuery(
      '''
        SELECT COALESCE(SUM(p.amount_minor), 0) AS paid
        FROM obligation_payments p
        JOIN transactions t ON t.id = p.transaction_id
        WHERE p.obligation_id = ? AND t.status = 'posted'
      ''',
      [obligationId],
    );
    return rows.single['paid']! as int;
  }

  Future<int> _fundedAmount(DatabaseExecutor txn, int obligationId) async {
    final rows = await txn.rawQuery(
      '''
        SELECT COALESCE(SUM(f.amount_minor), 0) AS funded
        FROM obligation_fundings f
        JOIN transactions t ON t.id = f.transaction_id
        WHERE f.obligation_id = ? AND t.status = 'posted'
      ''',
      [obligationId],
    );
    return rows.single['funded']! as int;
  }

  Future<int> _balance(DatabaseExecutor txn, int pocketId) async {
    final rows = await txn.rawQuery(
      '''
        SELECT COALESCE(SUM(e.amount_minor), 0) AS balance
        FROM ledger_entries e
        JOIN transactions t ON t.id = e.transaction_id
        WHERE e.pocket_id = ? AND t.status = 'posted'
      ''',
      [pocketId],
    );
    return rows.single['balance']! as int;
  }

  static void _validateFx(
    FxSettlement settlement, {
    required String sourceCurrency,
    required int sourceAmount,
    required String destinationCurrency,
    required int destinationAmount,
  }) {
    if (settlement.sourceCurrencyCode.toUpperCase() !=
            sourceCurrency.toUpperCase() ||
        settlement.sourceAmountMinor != sourceAmount ||
        settlement.destinationCurrencyCode.toUpperCase() !=
            destinationCurrency.toUpperCase() ||
        settlement.destinationAmountMinor != destinationAmount) {
      throw ArgumentError('FX details must match the actual money movement.');
    }
  }
}

class _Obligation {
  const _Obligation({
    required this.workspaceId,
    required this.counterpartyId,
    required this.categoryId,
    required this.direction,
    required this.nature,
    required this.currencyCode,
    required this.principalMinor,
  });

  final int workspaceId;
  final int counterpartyId;
  final int? categoryId;
  final String direction;
  final String nature;
  final String currencyCode;
  final int principalMinor;
}

class _Pocket {
  const _Pocket({
    required this.workspaceId,
    required this.currencyCode,
    required this.allowNegative,
  });

  final int workspaceId;
  final String currencyCode;
  final bool allowNegative;
}
