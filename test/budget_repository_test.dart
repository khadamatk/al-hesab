import 'package:al_hesab/features/budgets/data/budget_repository.dart';
import 'package:al_hesab/features/ledger/data/ledger_repository.dart';
import 'package:al_hesab/features/setup/data/finance_setup_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('budget usage triggers 80 and 100 percent alerts only once', () async {
    final appDatabase = createTestAppDatabase();
    addTearDown(appDatabase.close);
    final database = await appDatabase.open();
    final setup = FinanceSetupRepository(database);
    final ledger = LedgerRepository(database);
    final budgets = BudgetRepository(database);
    final workspaceId = await setup.workspaceId('شخصي');
    final foodId = await setup.categoryId(
      workspaceId: workspaceId,
      name: 'طعام',
      kind: 'expense',
    );
    final account = await setup.createAccount(
      workspaceId: workspaceId,
      name: 'الكاش',
      type: 'cash',
    );
    final pocket = await setup.createPocket(
      accountId: account,
      currencyCode: 'EGP',
    );
    await ledger.postOpeningBalance(
      workspaceId: workspaceId,
      pocketId: pocket,
      amountMinor: 200000,
      occurredOn: '2026-08-01',
    );
    final budgetId = await budgets.create(
      workspaceId: workspaceId,
      currencyCode: 'EGP',
      limitMinor: 100000,
      month: '2026-08',
      categoryId: foodId,
    );

    await ledger.postExpense(
      workspaceId: workspaceId,
      pocketId: pocket,
      amountMinor: 80000,
      categoryId: foodId,
      occurredOn: '2026-08-04',
    );
    var item = (await budgets.list(workspaceId, '2026-08')).single;
    expect(item.spentMinor, 80000);
    expect(item.triggeredLevels, {'threshold'});

    await ledger.postExpense(
      workspaceId: workspaceId,
      pocketId: pocket,
      amountMinor: 20000,
      categoryId: foodId,
      occurredOn: '2026-08-05',
    );
    item = (await budgets.list(workspaceId, '2026-08')).single;
    expect(item.triggeredLevels, {'threshold', 'exceeded'});
    await budgets.list(workspaceId, '2026-08');
    final alerts = await database.query(
      'budget_alerts',
      where: 'budget_id = ?',
      whereArgs: [budgetId],
    );
    expect(alerts, hasLength(2));
  });

  test(
    'budgets keep months, currencies, and general/category totals separate',
    () async {
      final appDatabase = createTestAppDatabase();
      addTearDown(appDatabase.close);
      final database = await appDatabase.open();
      final setup = FinanceSetupRepository(database);
      final ledger = LedgerRepository(database);
      final budgets = BudgetRepository(database);
      final workspaceId = await setup.workspaceId('فريلانس');
      final foodId = await setup.categoryId(
        workspaceId: workspaceId,
        name: 'طعام',
        kind: 'expense',
      );
      final account = await setup.createAccount(
        workspaceId: workspaceId,
        name: 'حساب',
        type: 'cash',
      );
      final egp = await setup.createPocket(
        accountId: account,
        currencyCode: 'EGP',
      );
      await ledger.postOpeningBalance(
        workspaceId: workspaceId,
        pocketId: egp,
        amountMinor: 50000,
        occurredOn: '2026-08-01',
      );
      await ledger.postExpense(
        workspaceId: workspaceId,
        pocketId: egp,
        amountMinor: 10000,
        categoryId: foodId,
        occurredOn: '2026-08-02',
      );
      await budgets.create(
        workspaceId: workspaceId,
        currencyCode: 'EGP',
        limitMinor: 50000,
        month: '2026-08',
      );
      await budgets.create(
        workspaceId: workspaceId,
        currencyCode: 'USD',
        limitMinor: 50000,
        month: '2026-08',
      );
      final items = await budgets.list(workspaceId, '2026-08');
      expect(
        items.firstWhere((e) => e.currencyCode == 'EGP').spentMinor,
        10000,
      );
      expect(items.firstWhere((e) => e.currencyCode == 'USD').spentMinor, 0);
      expect(await budgets.list(workspaceId, '2026-07'), isEmpty);
    },
  );
}
