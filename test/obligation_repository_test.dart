import 'package:al_hesab/core/database/app_database.dart';
import 'package:al_hesab/features/ledger/data/ledger_repository.dart';
import 'package:al_hesab/features/obligations/data/obligation_repository.dart';
import 'package:al_hesab/features/setup/data/finance_setup_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase appDatabase;
  late Database database;
  late FinanceSetupRepository setup;
  late LedgerRepository ledger;
  late ObligationRepository obligations;
  late int workspaceId;
  late int bankPocketId;
  late int counterpartyId;
  late int expenseCategoryId;
  late int incomeCategoryId;

  const day = '2026-08-04';
  DateTime clock() => DateTime.utc(2026, 8, 4, 12);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    appDatabase = createTestAppDatabase();
    database = await appDatabase.open();
    setup = FinanceSetupRepository(database, clock: clock);
    ledger = LedgerRepository(database, clock: clock);
    obligations = ObligationRepository(database, clock: clock);
    workspaceId = await setup.workspaceId('فريلانس');
    expenseCategoryId = await setup.categoryId(
      workspaceId: workspaceId,
      name: 'أخرى',
      kind: 'expense',
    );
    incomeCategoryId = await setup.categoryId(
      workspaceId: workspaceId,
      name: 'دخل مشروع',
      kind: 'income',
    );
    final bankId = await setup.createAccount(
      workspaceId: workspaceId,
      name: 'بنك الفريلانس',
      type: 'bank',
    );
    bankPocketId = await setup.createPocket(
      accountId: bankId,
      currencyCode: 'EGP',
    );
    counterpartyId = await setup.createCounterparty(
      workspaceId: workspaceId,
      name: 'عميل ومورد تجريبي',
      type: 'other',
    );
    await ledger.postOpeningBalance(
      workspaceId: workspaceId,
      pocketId: bankPocketId,
      amountMinor: 20000,
      occurredOn: day,
    );
  });

  tearDown(() => appDatabase.close());

  test(
    'payable supports partial payments, limit, completion, and void',
    () async {
      final obligationId = await obligations.create(
        workspaceId: workspaceId,
        counterpartyId: counterpartyId,
        direction: 'payable',
        nature: 'credit_purchase',
        currencyCode: 'EGP',
        categoryId: expenseCategoryId,
        principalMinor: 10000,
        openedOn: day,
      );
      await obligations.settle(
        obligationId: obligationId,
        pocketId: bankPocketId,
        obligationAmountMinor: 4000,
        pocketAmountMinor: 4000,
        occurredOn: day,
      );
      expect(await obligations.remaining(obligationId), 6000);
      expect(await ledger.pocketBalance(bankPocketId), 16000);
      final listed = (await obligations.list(workspaceId)).single;
      expect(listed.remainingMinor, 6000);
      expect(listed.status, 'partial');

      await expectLater(
        () => obligations.settle(
          obligationId: obligationId,
          pocketId: bankPocketId,
          obligationAmountMinor: 7000,
          pocketAmountMinor: 7000,
          occurredOn: day,
        ),
        throwsA(isA<StateError>()),
      );

      final finalPayment = await obligations.settle(
        obligationId: obligationId,
        pocketId: bankPocketId,
        obligationAmountMinor: 6000,
        pocketAmountMinor: 6000,
        occurredOn: day,
      );
      expect(await obligations.remaining(obligationId), 0);
      expect(
        (await database.query(
          'obligations',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [obligationId],
        )).single['status'],
        'settled',
      );

      await ledger.voidTransaction(finalPayment, 'إلغاء الدفعة الأخيرة');
      expect(await obligations.remaining(obligationId), 6000);
      expect(await ledger.pocketBalance(bankPocketId), 16000);
      expect(
        (await database.query(
          'obligations',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [obligationId],
        )).single['status'],
        'partial',
      );
    },
  );

  test(
    'invoice collection increases cash while money lent requires no income category',
    () async {
      final invoiceId = await obligations.create(
        workspaceId: workspaceId,
        counterpartyId: counterpartyId,
        direction: 'receivable',
        nature: 'invoice',
        currencyCode: 'EGP',
        categoryId: incomeCategoryId,
        principalMinor: 5000,
        openedOn: day,
      );
      await obligations.settle(
        obligationId: invoiceId,
        pocketId: bankPocketId,
        obligationAmountMinor: 5000,
        pocketAmountMinor: 5000,
        occurredOn: day,
      );
      expect(await ledger.pocketBalance(bankPocketId), 25000);

      final moneyLentId = await obligations.create(
        workspaceId: workspaceId,
        counterpartyId: counterpartyId,
        direction: 'receivable',
        nature: 'money_lent',
        currencyCode: 'EGP',
        principalMinor: 1000,
        openedOn: day,
      );
      expect(await obligations.remaining(moneyLentId), 1000);

      await expectLater(
        () => obligations.create(
          workspaceId: workspaceId,
          counterpartyId: counterpartyId,
          direction: 'receivable',
          nature: 'money_lent',
          currencyCode: 'EGP',
          categoryId: incomeCategoryId,
          principalMinor: 1000,
          openedOn: day,
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test('loan funding changes balance without creating income', () async {
    final loanId = await obligations.create(
      workspaceId: workspaceId,
      counterpartyId: counterpartyId,
      direction: 'payable',
      nature: 'loan',
      currencyCode: 'EGP',
      principalMinor: 12000,
      openedOn: day,
    );
    final transactionId = await obligations.fund(
      obligationId: loanId,
      pocketId: bankPocketId,
      obligationAmountMinor: 12000,
      pocketAmountMinor: 12000,
      occurredOn: day,
    );

    expect(await ledger.pocketBalance(bankPocketId), 32000);
    final transaction = (await database.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
    )).single;
    expect(transaction['type'], 'obligation_funding');
    expect(transaction['category_id'], isNull);
    expect(await countRows(database, 'obligation_fundings'), 1);
  });
}
