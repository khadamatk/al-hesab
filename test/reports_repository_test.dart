import 'package:al_hesab/features/ledger/data/ledger_repository.dart';
import 'package:al_hesab/features/obligations/data/obligation_repository.dart';
import 'package:al_hesab/features/reports/data/reports_repository.dart';
import 'package:al_hesab/features/setup/data/finance_setup_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'reports separate currencies and exclude transfers and voided entries',
    () async {
      final appDatabase = createTestAppDatabase();
      addTearDown(appDatabase.close);
      final database = await appDatabase.open();
      final setup = FinanceSetupRepository(database);
      final ledger = LedgerRepository(database);
      final obligations = ObligationRepository(database);
      final reports = ReportsRepository(database);
      final workspaceId = await setup.workspaceId('شخصي');
      final incomeId = await setup.categoryId(
        workspaceId: workspaceId,
        name: 'دخل آخر',
        kind: 'income',
      );
      final foodId = await setup.categoryId(
        workspaceId: workspaceId,
        name: 'طعام',
        kind: 'expense',
      );
      final bank = await setup.createAccount(
        workspaceId: workspaceId,
        name: 'البنك',
        type: 'bank',
      );
      final cash = await setup.createAccount(
        workspaceId: workspaceId,
        name: 'الكاش',
        type: 'cash',
      );
      final egpBank = await setup.createPocket(
        accountId: bank,
        currencyCode: 'EGP',
      );
      final egpCash = await setup.createPocket(
        accountId: cash,
        currencyCode: 'EGP',
      );
      final usd = await setup.createPocket(
        accountId: bank,
        currencyCode: 'USD',
      );
      await ledger.postOpeningBalance(
        workspaceId: workspaceId,
        pocketId: egpBank,
        amountMinor: 100000,
        occurredOn: '2026-08-01',
      );
      await ledger.postOpeningBalance(
        workspaceId: workspaceId,
        pocketId: usd,
        amountMinor: 5000,
        occurredOn: '2026-08-01',
      );
      await ledger.postIncome(
        workspaceId: workspaceId,
        pocketId: egpBank,
        amountMinor: 30000,
        categoryId: incomeId,
        occurredOn: '2026-08-02',
      );
      await ledger.postExpense(
        workspaceId: workspaceId,
        pocketId: egpBank,
        amountMinor: 10000,
        categoryId: foodId,
        occurredOn: '2026-08-03',
      );
      await ledger.postTransfer(
        workspaceId: workspaceId,
        sourcePocketId: egpBank,
        destinationPocketId: egpCash,
        sourceAmountMinor: 20000,
        occurredOn: '2026-08-04',
      );
      final voided = await ledger.postExpense(
        workspaceId: workspaceId,
        pocketId: egpCash,
        amountMinor: 5000,
        categoryId: foodId,
        occurredOn: '2026-08-05',
      );
      await ledger.voidTransaction(voided, 'اختبار التقرير');
      final party = await setup.createCounterparty(
        workspaceId: workspaceId,
        name: 'دائن',
        type: 'lender',
      );
      await obligations.create(
        workspaceId: workspaceId,
        counterpartyId: party,
        direction: 'payable',
        nature: 'loan',
        currencyCode: 'USD',
        principalMinor: 2000,
        openedOn: '2026-08-01',
      );

      final report = await reports.load(workspaceId, '2026-08');
      final egpFlow = report.cashFlow.singleWhere(
        (e) => e.currencyCode == 'EGP',
      );
      expect(egpFlow.incomeMinor, 30000);
      expect(egpFlow.expenseMinor, 10000);
      expect(egpFlow.netMinor, 20000);
      final oneDay = await reports.loadRange(
        workspaceId,
        '2026-08-03',
        '2026-08-03',
      );
      expect(oneDay.cashFlow.single.expenseMinor, 10000);
      expect(oneDay.cashFlow.single.incomeMinor, 0);
      expect(
        report.balances
            .where((e) => e.currencyCode == 'EGP')
            .fold<int>(0, (sum, e) => sum + e.balanceMinor),
        120000,
      );
      expect(
        report.balances
            .singleWhere((e) => e.currencyCode == 'USD')
            .balanceMinor,
        5000,
      );
      expect(
        report.categories.singleWhere((e) => e.name == 'طعام').amountMinor,
        10000,
      );
      expect(
        report.obligations
            .singleWhere((e) => e.currencyCode == 'USD')
            .payableMinor,
        2000,
      );
    },
  );

  test('reports isolate workspaces and months', () async {
    final appDatabase = createTestAppDatabase();
    addTearDown(appDatabase.close);
    final database = await appDatabase.open();
    final setup = FinanceSetupRepository(database);
    final ledger = LedgerRepository(database);
    final reports = ReportsRepository(database);
    final personal = await setup.workspaceId('شخصي');
    final company = await setup.workspaceId('الشركة');
    final income = await setup.categoryId(
      workspaceId: company,
      name: 'دخل آخر',
      kind: 'income',
    );
    final account = await setup.createAccount(
      workspaceId: company,
      name: 'بنك الشركة',
      type: 'bank',
    );
    final pocket = await setup.createPocket(
      accountId: account,
      currencyCode: 'EGP',
    );
    await ledger.postIncome(
      workspaceId: company,
      pocketId: pocket,
      amountMinor: 10000,
      categoryId: income,
      occurredOn: '2026-07-10',
    );
    expect((await reports.load(personal, '2026-07')).cashFlow, isEmpty);
    expect((await reports.load(company, '2026-08')).cashFlow, isEmpty);
    expect(
      (await reports.load(company, '2026-07')).cashFlow.single.incomeMinor,
      10000,
    );
  });

  test('split expense is debited once and reported by allocation', () async {
    final appDatabase = createTestAppDatabase();
    addTearDown(appDatabase.close);
    final database = await appDatabase.open();
    final setup = FinanceSetupRepository(database);
    final ledger = LedgerRepository(database);
    final reports = ReportsRepository(database);
    final workspace = await setup.workspaceId('شخصي');
    final food = await setup.categoryId(
      workspaceId: workspace,
      name: 'طعام',
      kind: 'expense',
    );
    final fees = await setup.categoryId(
      workspaceId: workspace,
      name: 'رسوم وعمولات',
      kind: 'expense',
    );
    final account = await setup.createAccount(
      workspaceId: workspace,
      name: 'اختبار التقسيم',
      type: 'cash',
    );
    final pocket = await setup.createPocket(
      accountId: account,
      currencyCode: 'EGP',
    );
    await ledger.postOpeningBalance(
      workspaceId: workspace,
      pocketId: pocket,
      amountMinor: 20000,
      occurredOn: '2026-08-10',
    );
    await ledger.postSplitExpense(
      workspaceId: workspace,
      pocketId: pocket,
      amountMinor: 10000,
      splits: [
        SplitAllocation(categoryId: food, amountMinor: 7000),
        SplitAllocation(categoryId: fees, amountMinor: 3000),
      ],
      occurredOn: '2026-08-10',
    );

    expect(await ledger.pocketBalance(pocket), 10000);
    final report = await reports.load(workspace, '2026-08');
    expect(report.cashFlow.single.expenseMinor, 10000);
    expect(
      report.categories.singleWhere((e) => e.name == 'طعام').amountMinor,
      7000,
    );
    expect(
      report.categories
          .singleWhere((e) => e.name == 'رسوم وعمولات')
          .amountMinor,
      3000,
    );
  });
}
