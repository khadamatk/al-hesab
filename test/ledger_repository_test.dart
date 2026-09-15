import 'package:al_hesab/core/database/app_database.dart';
import 'package:al_hesab/features/ledger/data/ledger_repository.dart';
import 'package:al_hesab/features/setup/data/finance_setup_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase appDatabase;
  late Database database;
  late FinanceSetupRepository setup;
  late LedgerRepository ledger;
  late int workspaceId;
  late int bankAccountId;
  late int bankEgpPocketId;
  late int cashEgpPocketId;
  late int paypalUsdPocketId;
  late int paypalMadPocketId;
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
    workspaceId = await setup.workspaceId('شخصي');
    expenseCategoryId = await setup.categoryId(
      workspaceId: workspaceId,
      name: 'رسوم وعمولات',
      kind: 'expense',
    );
    incomeCategoryId = await setup.categoryId(
      workspaceId: workspaceId,
      name: 'دخل آخر',
      kind: 'income',
    );

    bankAccountId = await setup.createAccount(
      workspaceId: workspaceId,
      name: 'البنك',
      type: 'bank',
    );
    bankEgpPocketId = await setup.createPocket(
      accountId: bankAccountId,
      currencyCode: 'EGP',
    );
    final cashAccountId = await setup.createAccount(
      workspaceId: workspaceId,
      name: 'الكاش',
      type: 'cash',
    );
    cashEgpPocketId = await setup.createPocket(
      accountId: cashAccountId,
      currencyCode: 'EGP',
    );
    final paypalAccountId = await setup.createAccount(
      workspaceId: workspaceId,
      name: 'PayPal',
      type: 'paypal',
    );
    paypalUsdPocketId = await setup.createPocket(
      accountId: paypalAccountId,
      currencyCode: 'USD',
    );
    paypalMadPocketId = await setup.createPocket(
      accountId: paypalAccountId,
      currencyCode: 'MAD',
    );
  });

  tearDown(() => appDatabase.close());

  test(
    'income, ATM transfer, fee, and void produce auditable balances',
    () async {
      await ledger.postOpeningBalance(
        workspaceId: workspaceId,
        pocketId: bankEgpPocketId,
        amountMinor: 100000,
        occurredOn: day,
      );
      await ledger.postIncome(
        workspaceId: workspaceId,
        pocketId: bankEgpPocketId,
        amountMinor: 5000,
        categoryId: incomeCategoryId,
        occurredOn: day,
      );
      final atmId = await setup.createChannel(
        workspaceId: workspaceId,
        name: 'ATM',
        type: 'atm',
      );
      final transferId = await ledger.postTransfer(
        workspaceId: workspaceId,
        sourcePocketId: bankEgpPocketId,
        destinationPocketId: cashEgpPocketId,
        sourceAmountMinor: 20000,
        occurredOn: day,
        channelId: atmId,
      );
      final feeId = await ledger.postExpense(
        workspaceId: workspaceId,
        pocketId: bankEgpPocketId,
        amountMinor: 500,
        categoryId: expenseCategoryId,
        occurredOn: day,
        relatedTransactionId: transferId,
      );

      expect(await ledger.pocketBalance(bankEgpPocketId), 84500);
      expect(await ledger.pocketBalance(cashEgpPocketId), 20000);
      final history = await ledger.listTransactions(workspaceId);
      expect(history, hasLength(4));
      expect(history.first.type, 'expense');

      await ledger.voidTransaction(feeId, 'تم رد العمولة');
      expect(await ledger.pocketBalance(bankEgpPocketId), 85000);
      expect(await ledger.listTransactions(workspaceId), hasLength(3));
    },
  );

  test(
    'PayPal keeps pockets separate and records explicit FX amounts',
    () async {
      await ledger.postOpeningBalance(
        workspaceId: workspaceId,
        pocketId: paypalUsdPocketId,
        amountMinor: 10000,
        occurredOn: day,
      );
      final transactionId = await ledger.postTransfer(
        workspaceId: workspaceId,
        sourcePocketId: paypalUsdPocketId,
        destinationPocketId: paypalMadPocketId,
        sourceAmountMinor: 5000,
        destinationAmountMinor: 48500,
        occurredOn: day,
      );

      expect(await ledger.pocketBalance(paypalUsdPocketId), 5000);
      expect(await ledger.pocketBalance(paypalMadPocketId), 48500);
      final fx = await database.query(
        'transaction_fx_details',
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
      );
      expect(fx.single['source_currency_code'], 'USD');
      expect(fx.single['source_amount_minor'], 5000);
      expect(fx.single['destination_currency_code'], 'MAD');
      expect(fx.single['destination_amount_minor'], 48500);
    },
  );

  test(
    'correction voids the old expense and posts the replacement atomically',
    () async {
      await ledger.postOpeningBalance(
        workspaceId: workspaceId,
        pocketId: bankEgpPocketId,
        amountMinor: 100000,
        occurredOn: day,
      );
      await ledger.postOpeningBalance(
        workspaceId: workspaceId,
        pocketId: cashEgpPocketId,
        amountMinor: 10000,
        occurredOn: day,
      );
      final oldId = await ledger.postExpense(
        workspaceId: workspaceId,
        pocketId: bankEgpPocketId,
        amountMinor: 10000,
        categoryId: expenseCategoryId,
        occurredOn: day,
        note: 'wrong',
      );
      final replacementId = await ledger.correctTransaction(
        transactionId: oldId,
        workspaceId: workspaceId,
        sourcePocketId: cashEgpPocketId,
        amountMinor: 5000,
        categoryId: expenseCategoryId,
        occurredOn: '2026-08-05',
        note: 'fixed',
      );
      final old = (await database.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [oldId],
      )).single;
      final replacement = (await database.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [replacementId],
      )).single;
      expect(old['status'], 'voided');
      expect(replacement['related_transaction_id'], oldId);
      expect(await ledger.pocketBalance(bankEgpPocketId), 100000);
      expect(await ledger.pocketBalance(cashEgpPocketId), 5000);
    },
  );

  test(
    'external PayPal settlement stores recipient amount without fake account',
    () async {
      await ledger.postOpeningBalance(
        workspaceId: workspaceId,
        pocketId: paypalUsdPocketId,
        amountMinor: 10000,
        occurredOn: day,
      );
      final transactionId = await ledger.postExpense(
        workspaceId: workspaceId,
        pocketId: paypalUsdPocketId,
        amountMinor: 2500,
        categoryId: expenseCategoryId,
        occurredOn: day,
        externalSettlement: const FxSettlement(
          sourceCurrencyCode: 'USD',
          sourceAmountMinor: 2500,
          destinationCurrencyCode: 'MAD',
          destinationAmountMinor: 24250,
        ),
      );

      expect(await ledger.pocketBalance(paypalUsdPocketId), 7500);
      expect(
        await countRows(database, 'account_pockets'),
        4,
        reason: 'No recipient-owned pocket should be created.',
      );
      expect(
        await database.query(
          'transaction_fx_details',
          where: 'transaction_id = ?',
          whereArgs: [transactionId],
        ),
        hasLength(1),
      );
    },
  );

  test('InstaPay affects only a linked bank account', () async {
    await ledger.postOpeningBalance(
      workspaceId: workspaceId,
      pocketId: bankEgpPocketId,
      amountMinor: 10000,
      occurredOn: day,
    );
    final instaPayId = await setup.createChannel(
      workspaceId: workspaceId,
      name: 'InstaPay',
      type: 'instapay',
    );
    await setup.linkChannelToAccount(
      channelId: instaPayId,
      accountId: bankAccountId,
    );
    await ledger.postExpense(
      workspaceId: workspaceId,
      pocketId: bankEgpPocketId,
      amountMinor: 1000,
      categoryId: expenseCategoryId,
      occurredOn: day,
      channelId: instaPayId,
    );
    expect(await ledger.pocketBalance(bankEgpPocketId), 9000);
    expect(await countRows(database, 'account_pockets'), 4);

    await expectLater(
      () => ledger.postExpense(
        workspaceId: workspaceId,
        pocketId: cashEgpPocketId,
        amountMinor: 1,
        categoryId: expenseCategoryId,
        occurredOn: day,
        channelId: instaPayId,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects workspace leakage and insufficient balances', () async {
    final companyId = await setup.workspaceId('الشركة');
    final companyCash = await setup.createAccount(
      workspaceId: companyId,
      name: 'خزنة الشركة',
      type: 'cash',
    );
    final companyPocket = await setup.createPocket(
      accountId: companyCash,
      currencyCode: 'EGP',
    );

    await expectLater(
      () => ledger.postTransfer(
        workspaceId: workspaceId,
        sourcePocketId: bankEgpPocketId,
        destinationPocketId: companyPocket,
        sourceAmountMinor: 1,
        occurredOn: day,
      ),
      throwsA(anyOf(isA<StateError>(), isA<DatabaseException>())),
    );
    await expectLater(
      () => ledger.postExpense(
        workspaceId: workspaceId,
        pocketId: bankEgpPocketId,
        amountMinor: 1,
        categoryId: expenseCategoryId,
        occurredOn: day,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
