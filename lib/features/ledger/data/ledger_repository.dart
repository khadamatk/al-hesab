import 'package:sqflite/sqflite.dart';

class TransactionItem {
  const TransactionItem({
    required this.id,
    required this.type,
    required this.occurredOn,
    required this.amountMinor,
    required this.currencyCode,
    required this.sourcePocketId,
    this.destinationPocketId,
    this.destinationAmountMinor,
    this.categoryId,
    this.counterpartyId,
    this.channelId,
    this.note,
    this.splitCategoryIds = const [],
  });
  final int id;
  final String type;
  final String occurredOn;
  final int amountMinor;
  final String currencyCode;
  final int sourcePocketId;
  final int? destinationPocketId,
      destinationAmountMinor,
      categoryId,
      counterpartyId,
      channelId;
  final String? note;
  final List<int> splitCategoryIds;
}

class FxSettlement {
  const FxSettlement({
    required this.sourceCurrencyCode,
    required this.sourceAmountMinor,
    required this.destinationCurrencyCode,
    required this.destinationAmountMinor,
  });

  final String sourceCurrencyCode;
  final int sourceAmountMinor;
  final String destinationCurrencyCode;
  final int destinationAmountMinor;
}

class SplitAllocation {
  const SplitAllocation({required this.categoryId, required this.amountMinor});
  final int categoryId;
  final int amountMinor;
}

class LedgerRepository {
  LedgerRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Database _database;
  final DateTime Function() _clock;

  String get _timestamp => _clock().toUtc().toIso8601String();

  Future<List<TransactionItem>> listTransactions(int workspaceId) async {
    final rows = await _database.rawQuery(
      '''
      SELECT t.id, t.type, t.occurred_on, t.note, t.category_id,
        t.counterparty_id, t.channel_id,
        GROUP_CONCAT(DISTINCT s.category_id) split_category_ids,
        COALESCE(MAX(CASE WHEN e.role IN ('source','single') THEN ABS(e.amount_minor) END), 0) amount_minor,
        GROUP_CONCAT(DISTINCT p.currency_code) currency_code,
        MAX(CASE WHEN e.role IN ('source','single') THEN e.pocket_id END) source_pocket_id,
        MAX(CASE WHEN e.role = 'destination' THEN e.pocket_id END) destination_pocket_id,
        MAX(CASE WHEN e.role = 'destination' THEN ABS(e.amount_minor) END) destination_amount_minor
      FROM transactions t
      LEFT JOIN ledger_entries e ON e.transaction_id = t.id
      LEFT JOIN account_pockets p ON p.id = e.pocket_id
      LEFT JOIN transaction_splits s ON s.transaction_id = t.id
      WHERE t.workspace_id = ? AND t.status = 'posted'
      GROUP BY t.id ORDER BY t.occurred_on DESC, t.id DESC
    ''',
      [workspaceId],
    );
    return rows
        .map(
          (r) => TransactionItem(
            id: r['id']! as int,
            type: r['type']! as String,
            occurredOn: r['occurred_on']! as String,
            amountMinor: r['amount_minor']! as int,
            currencyCode: (r['currency_code'] as String?) ?? '',
            sourcePocketId: r['source_pocket_id']! as int,
            destinationPocketId: r['destination_pocket_id'] as int?,
            destinationAmountMinor: r['destination_amount_minor'] as int?,
            categoryId: r['category_id'] as int?,
            counterpartyId: r['counterparty_id'] as int?,
            channelId: r['channel_id'] as int?,
            note: r['note'] as String?,
            splitCategoryIds:
                (r['split_category_ids'] as String?)
                    ?.split(',')
                    .map(int.parse)
                    .toList() ??
                const [],
          ),
        )
        .toList();
  }

  Future<int> postOpeningBalance({
    required int workspaceId,
    required int pocketId,
    required int amountMinor,
    required String occurredOn,
    String note = 'الرصيد الافتتاحي',
  }) {
    if (amountMinor == 0) {
      throw ArgumentError('Opening balance cannot be zero.');
    }
    return _postSingle(
      workspaceId: workspaceId,
      pocketId: pocketId,
      amountMinor: amountMinor,
      type: 'opening_balance',
      occurredOn: occurredOn,
      note: note,
    );
  }

  Future<int> postIncome({
    required int workspaceId,
    required int pocketId,
    required int amountMinor,
    required int categoryId,
    required String occurredOn,
    int? counterpartyId,
    int? channelId,
    String? note,
  }) {
    _requirePositive(amountMinor);
    return _postSingle(
      workspaceId: workspaceId,
      pocketId: pocketId,
      amountMinor: amountMinor,
      type: 'income',
      categoryId: categoryId,
      counterpartyId: counterpartyId,
      channelId: channelId,
      occurredOn: occurredOn,
      note: note,
    );
  }

  Future<int> postExpense({
    required int workspaceId,
    required int pocketId,
    required int amountMinor,
    required int categoryId,
    required String occurredOn,
    int? counterpartyId,
    int? channelId,
    int? relatedTransactionId,
    FxSettlement? externalSettlement,
    String? note,
  }) async {
    _requirePositive(amountMinor);
    return _database.transaction((txn) async {
      final pocket = await _pocketDetails(txn, pocketId);
      await _ensureSufficientBalance(txn, pocketId, amountMinor);
      if (externalSettlement != null &&
          (externalSettlement.sourceCurrencyCode.toUpperCase() !=
                  pocket.currencyCode.toUpperCase() ||
              externalSettlement.sourceAmountMinor != amountMinor)) {
        throw ArgumentError(
          'External settlement source must match the debited pocket and amount.',
        );
      }
      final transactionId = await _insertTransaction(
        txn,
        workspaceId: workspaceId,
        type: 'expense',
        categoryId: categoryId,
        counterpartyId: counterpartyId,
        channelId: channelId,
        relatedTransactionId: relatedTransactionId,
        occurredOn: occurredOn,
        note: note,
      );
      await _insertEntry(
        txn,
        transactionId: transactionId,
        pocketId: pocketId,
        role: 'single',
        amountMinor: -amountMinor,
      );
      if (externalSettlement != null) {
        await _insertFx(txn, transactionId, externalSettlement);
      }
      await _ensureChannelLinked(txn, channelId, [pocketId]);
      return transactionId;
    });
  }

  Future<int> postSplitExpense({
    required int workspaceId,
    required int pocketId,
    required int amountMinor,
    required List<SplitAllocation> splits,
    required String occurredOn,
    int? counterpartyId,
    int? channelId,
    String? note,
  }) async {
    _requirePositive(amountMinor);
    if (splits.length < 2 ||
        splits.map((split) => split.categoryId).toSet().length !=
            splits.length ||
        splits.any((split) => split.amountMinor <= 0) ||
        splits.fold<int>(0, (sum, split) => sum + split.amountMinor) !=
            amountMinor) {
      throw ArgumentError(
        'Split allocations must be positive and equal total.',
      );
    }
    return _database.transaction((txn) async {
      final pocket = await _pocketDetails(txn, pocketId);
      if (pocket.workspaceId != workspaceId) {
        throw StateError('Pocket belongs to another workspace.');
      }
      await _ensureSufficientBalance(txn, pocketId, amountMinor);
      for (final split in splits) {
        final category = await txn.query(
          'categories',
          columns: ['workspace_id', 'kind'],
          where: 'id = ? AND is_archived = 0',
          whereArgs: [split.categoryId],
          limit: 1,
        );
        if (category.isEmpty ||
            category.single['workspace_id'] != workspaceId ||
            category.single['kind'] != 'expense') {
          throw StateError('Split category is invalid.');
        }
      }
      final transactionId = await _insertTransaction(
        txn,
        workspaceId: workspaceId,
        type: 'expense',
        // The first category keeps the original transaction integrity trigger
        // valid; reporting detects split rows and uses their allocations.
        categoryId: splits.first.categoryId,
        counterpartyId: counterpartyId,
        channelId: channelId,
        occurredOn: occurredOn,
        note: note,
      );
      await _insertEntry(
        txn,
        transactionId: transactionId,
        pocketId: pocketId,
        role: 'single',
        amountMinor: -amountMinor,
      );
      for (final split in splits) {
        await txn.insert('transaction_splits', {
          'transaction_id': transactionId,
          'category_id': split.categoryId,
          'amount_minor': split.amountMinor,
          'created_at': _timestamp,
        });
      }
      await _ensureChannelLinked(txn, channelId, [pocketId]);
      return transactionId;
    });
  }

  Future<int> postTransfer({
    required int workspaceId,
    required int sourcePocketId,
    required int destinationPocketId,
    required int sourceAmountMinor,
    required String occurredOn,
    int? destinationAmountMinor,
    int? channelId,
    String? note,
  }) async {
    _requirePositive(sourceAmountMinor);
    if (sourcePocketId == destinationPocketId) {
      throw ArgumentError('Transfer pockets must be different.');
    }

    return _database.transaction((txn) async {
      final source = await _pocketDetails(txn, sourcePocketId);
      final destination = await _pocketDetails(txn, destinationPocketId);
      if (source.workspaceId != workspaceId ||
          destination.workspaceId != workspaceId) {
        throw StateError('Transfers cannot cross workspaces.');
      }

      final sameCurrency =
          source.currencyCode.toUpperCase() ==
          destination.currencyCode.toUpperCase();
      final received = destinationAmountMinor ?? sourceAmountMinor;
      _requirePositive(received);
      if (sameCurrency && received != sourceAmountMinor) {
        throw ArgumentError('Same-currency transfers must use equal amounts.');
      }
      if (!sameCurrency && destinationAmountMinor == null) {
        throw ArgumentError(
          'Cross-currency transfers require the received amount.',
        );
      }

      await _ensureSufficientBalance(txn, sourcePocketId, sourceAmountMinor);
      final transactionId = await _insertTransaction(
        txn,
        workspaceId: workspaceId,
        type: 'transfer',
        channelId: channelId,
        occurredOn: occurredOn,
        note: note,
      );
      await _insertEntry(
        txn,
        transactionId: transactionId,
        pocketId: sourcePocketId,
        role: 'source',
        amountMinor: -sourceAmountMinor,
      );
      await _insertEntry(
        txn,
        transactionId: transactionId,
        pocketId: destinationPocketId,
        role: 'destination',
        amountMinor: received,
      );
      if (!sameCurrency) {
        await _insertFx(
          txn,
          transactionId,
          FxSettlement(
            sourceCurrencyCode: source.currencyCode,
            sourceAmountMinor: sourceAmountMinor,
            destinationCurrencyCode: destination.currencyCode,
            destinationAmountMinor: received,
          ),
        );
      }
      await _ensureChannelLinked(txn, channelId, [
        sourcePocketId,
        destinationPocketId,
      ]);
      return transactionId;
    });
  }

  Future<void> voidTransaction(int transactionId, String reason) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw ArgumentError('Void reason is required.');
    await _database.transaction((txn) async {
      final changed = await txn.update(
        'transactions',
        {'status': 'voided', 'void_reason': trimmed, 'updated_at': _timestamp},
        where: 'id = ? AND status = ?',
        whereArgs: [transactionId, 'posted'],
      );
      if (changed != 1) throw StateError('Posted transaction not found.');

      final payment = await txn.query(
        'obligation_payments',
        columns: ['obligation_id'],
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (payment.isNotEmpty) {
        final obligationId = payment.single['obligation_id']! as int;
        final rows = await txn.rawQuery(
          '''
            SELECT o.principal_minor,
              COALESCE(SUM(CASE WHEN t.status = 'posted' THEN p.amount_minor ELSE 0 END), 0) AS paid
            FROM obligations o
            LEFT JOIN obligation_payments p ON p.obligation_id = o.id
            LEFT JOIN transactions t ON t.id = p.transaction_id
            WHERE o.id = ?
            GROUP BY o.id
          ''',
          [obligationId],
        );
        final principal = rows.single['principal_minor']! as int;
        final paid = rows.single['paid']! as int;
        await txn.update(
          'obligations',
          {
            'status': paid == 0
                ? 'open'
                : paid == principal
                ? 'settled'
                : 'partial',
            'updated_at': _timestamp,
          },
          where: 'id = ? AND status != ?',
          whereArgs: [obligationId, 'cancelled'],
        );
      }
    });
  }

  Future<int> correctTransaction({
    required int transactionId,
    required int workspaceId,
    required int sourcePocketId,
    required int amountMinor,
    required String occurredOn,
    int? destinationPocketId,
    int? destinationAmountMinor,
    int? categoryId,
    int? counterpartyId,
    int? channelId,
    String? note,
  }) async {
    _requirePositive(amountMinor);
    return _database.transaction((txn) async {
      final oldRows = await txn.query(
        'transactions',
        where: 'id = ? AND workspace_id = ? AND status = ?',
        whereArgs: [transactionId, workspaceId, 'posted'],
        limit: 1,
      );
      if (oldRows.isEmpty) throw StateError('Posted transaction not found.');
      final type = oldRows.single['type']! as String;
      if (!const {
        'income',
        'expense',
        'transfer',
        'opening_balance',
      }.contains(type)) {
        throw StateError('This transaction type cannot be corrected here.');
      }
      await txn.update(
        'transactions',
        {
          'status': 'voided',
          'void_reason': 'تم تصحيح العملية',
          'updated_at': _timestamp,
        },
        where: 'id = ?',
        whereArgs: [transactionId],
      );

      final source = await _pocketDetails(txn, sourcePocketId);
      if (source.workspaceId != workspaceId) {
        throw StateError('Pocket belongs to another workspace.');
      }
      if (type == 'expense' || type == 'transfer') {
        await _ensureSufficientBalance(txn, sourcePocketId, amountMinor);
      }
      final newId = await _insertTransaction(
        txn,
        workspaceId: workspaceId,
        type: type,
        categoryId: categoryId,
        counterpartyId: counterpartyId,
        channelId: channelId,
        relatedTransactionId: transactionId,
        occurredOn: occurredOn,
        note: note,
      );
      if (type == 'transfer') {
        if (destinationPocketId == null ||
            destinationPocketId == sourcePocketId) {
          throw ArgumentError('Transfer destination is required.');
        }
        final destination = await _pocketDetails(txn, destinationPocketId);
        if (destination.workspaceId != workspaceId) {
          throw StateError('Pocket belongs to another workspace.');
        }
        final sameCurrency =
            source.currencyCode.toUpperCase() ==
            destination.currencyCode.toUpperCase();
        final received = sameCurrency ? amountMinor : destinationAmountMinor;
        if (received == null || received <= 0) {
          throw ArgumentError('Received amount is required.');
        }
        await _insertEntry(
          txn,
          transactionId: newId,
          pocketId: sourcePocketId,
          role: 'source',
          amountMinor: -amountMinor,
        );
        await _insertEntry(
          txn,
          transactionId: newId,
          pocketId: destinationPocketId,
          role: 'destination',
          amountMinor: received,
        );
        if (!sameCurrency) {
          await _insertFx(
            txn,
            newId,
            FxSettlement(
              sourceCurrencyCode: source.currencyCode,
              sourceAmountMinor: amountMinor,
              destinationCurrencyCode: destination.currencyCode,
              destinationAmountMinor: received,
            ),
          );
        }
        await _ensureChannelLinked(txn, channelId, [
          sourcePocketId,
          destinationPocketId,
        ]);
      } else {
        if ((type == 'income' || type == 'expense') && categoryId == null) {
          throw ArgumentError('Category is required.');
        }
        final signedAmount = type == 'expense' ? -amountMinor : amountMinor;
        await _insertEntry(
          txn,
          transactionId: newId,
          pocketId: sourcePocketId,
          role: 'single',
          amountMinor: signedAmount,
        );
        await _ensureChannelLinked(txn, channelId, [sourcePocketId]);
      }
      return newId;
    });
  }

  Future<int> pocketBalance(int pocketId) async {
    final rows = await _database.rawQuery(
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

  Future<int> _postSingle({
    required int workspaceId,
    required int pocketId,
    required int amountMinor,
    required String type,
    required String occurredOn,
    int? categoryId,
    int? counterpartyId,
    int? channelId,
    String? note,
  }) {
    return _database.transaction((txn) async {
      final transactionId = await _insertTransaction(
        txn,
        workspaceId: workspaceId,
        type: type,
        categoryId: categoryId,
        counterpartyId: counterpartyId,
        channelId: channelId,
        occurredOn: occurredOn,
        note: note,
      );
      await _insertEntry(
        txn,
        transactionId: transactionId,
        pocketId: pocketId,
        role: 'single',
        amountMinor: amountMinor,
      );
      await _ensureChannelLinked(txn, channelId, [pocketId]);
      return transactionId;
    });
  }

  Future<int> _insertTransaction(
    DatabaseExecutor txn, {
    required int workspaceId,
    required String type,
    required String occurredOn,
    int? categoryId,
    int? counterpartyId,
    int? channelId,
    int? relatedTransactionId,
    String? note,
  }) {
    return txn.insert('transactions', {
      'workspace_id': workspaceId,
      'type': type,
      'category_id': categoryId,
      'counterparty_id': counterpartyId,
      'channel_id': channelId,
      'related_transaction_id': relatedTransactionId,
      'occurred_on': occurredOn,
      'note': note?.trim(),
      'created_at': _timestamp,
      'updated_at': _timestamp,
    });
  }

  Future<void> _insertEntry(
    DatabaseExecutor txn, {
    required int transactionId,
    required int pocketId,
    required String role,
    required int amountMinor,
  }) async {
    await txn.insert('ledger_entries', {
      'transaction_id': transactionId,
      'pocket_id': pocketId,
      'role': role,
      'amount_minor': amountMinor,
      'created_at': _timestamp,
    });
  }

  Future<void> _insertFx(
    DatabaseExecutor txn,
    int transactionId,
    FxSettlement settlement,
  ) async {
    _requirePositive(settlement.sourceAmountMinor);
    _requirePositive(settlement.destinationAmountMinor);
    await txn.insert('transaction_fx_details', {
      'transaction_id': transactionId,
      'source_currency_code': settlement.sourceCurrencyCode.toUpperCase(),
      'source_amount_minor': settlement.sourceAmountMinor,
      'destination_currency_code': settlement.destinationCurrencyCode
          .toUpperCase(),
      'destination_amount_minor': settlement.destinationAmountMinor,
      'created_at': _timestamp,
    });
  }

  Future<_PocketDetails> _pocketDetails(
    DatabaseExecutor txn,
    int pocketId,
  ) async {
    final rows = await txn.rawQuery(
      '''
        SELECT p.currency_code, a.workspace_id, a.allow_negative, a.id AS account_id
        FROM account_pockets p
        JOIN accounts a ON a.id = p.account_id
        WHERE p.id = ? AND p.is_archived = 0 AND a.is_archived = 0
      ''',
      [pocketId],
    );
    if (rows.isEmpty) throw StateError('Active pocket not found: $pocketId');
    final row = rows.single;
    return _PocketDetails(
      workspaceId: row['workspace_id']! as int,
      accountId: row['account_id']! as int,
      currencyCode: row['currency_code']! as String,
      allowNegative: row['allow_negative'] == 1,
    );
  }

  Future<void> _ensureSufficientBalance(
    DatabaseExecutor txn,
    int pocketId,
    int amountMinor,
  ) async {
    final pocket = await _pocketDetails(txn, pocketId);
    if (pocket.allowNegative) return;
    final rows = await txn.rawQuery(
      '''
        SELECT COALESCE(SUM(e.amount_minor), 0) AS balance
        FROM ledger_entries e
        JOIN transactions t ON t.id = e.transaction_id
        WHERE e.pocket_id = ? AND t.status = 'posted'
      ''',
      [pocketId],
    );
    final balance = rows.single['balance']! as int;
    if (balance < amountMinor) throw StateError('Insufficient pocket balance.');
  }

  Future<void> _ensureChannelLinked(
    DatabaseExecutor txn,
    int? channelId,
    List<int> pocketIds,
  ) async {
    if (channelId == null) return;
    final channel = await txn.query(
      'payment_channels',
      columns: ['type'],
      where: 'id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (channel.isEmpty || channel.single['type'] != 'instapay') return;
    final placeholders = List.filled(pocketIds.length, '?').join(',');
    final linked = await txn.rawQuery(
      '''
        SELECT 1
        FROM account_pockets p
        JOIN channel_accounts ca ON ca.account_id = p.account_id
        WHERE ca.channel_id = ? AND p.id IN ($placeholders)
        LIMIT 1
      ''',
      [channelId, ...pocketIds],
    );
    if (linked.isEmpty) {
      throw StateError('InstaPay must be linked to a participating account.');
    }
  }

  static void _requirePositive(int amountMinor) {
    if (amountMinor <= 0) throw ArgumentError('Amount must be positive.');
  }
}

class _PocketDetails {
  const _PocketDetails({
    required this.workspaceId,
    required this.accountId,
    required this.currencyCode,
    required this.allowNegative,
  });

  final int workspaceId;
  final int accountId;
  final String currencyCode;
  final bool allowNegative;
}
