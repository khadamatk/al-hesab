import 'package:al_hesab/features/setup/data/finance_setup_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('new workspace receives default categories', () async {
    final db = createTestAppDatabase();
    addTearDown(db.close);
    final repo = FinanceSetupRepository(await db.open());
    final id = await repo.createWorkspace(name: 'مشروع جديد', type: 'business');
    final items = await repo.listCategories(id);
    expect(items, hasLength(8));
    expect(items.where((e) => e.type == 'income'), hasLength(3));
    expect(items.where((e) => e.type == 'expense'), hasLength(5));
  });

  test('account owns multiple currency pockets', () async {
    final db = createTestAppDatabase();
    addTearDown(db.close);
    final repo = FinanceSetupRepository(await db.open());
    final workspaceId = await repo.workspaceId('شخصي');
    final accountId = await repo.createAccount(
      workspaceId: workspaceId,
      name: 'PayPal',
      type: 'paypal',
    );
    await repo.createPocket(accountId: accountId, currencyCode: 'USD');
    await repo.createPocket(accountId: accountId, currencyCode: 'MAD');
    final account = (await repo.listAccounts(workspaceId)).single;
    expect(
      account.pockets.map((e) => e.currencyCode),
      containsAll(['USD', 'MAD']),
    );
    expect(account.pockets.every((e) => e.balanceMinor == 0), isTrue);
    expect(
      account.pockets.singleWhere((e) => e.currencyCode == 'USD').isDefault,
      isTrue,
    );
  });

  test('default and recently used currency pockets are listed first', () async {
    final db = createTestAppDatabase();
    addTearDown(db.close);
    final repo = FinanceSetupRepository(await db.open());
    final workspaceId = await repo.createWorkspace(
      name: 'Pocket priority test',
      type: 'personal',
    );
    final accountId = await repo.createAccount(
      workspaceId: workspaceId,
      name: 'في جيبي',
      type: 'cash',
    );
    final egp = await repo.createPocket(
      accountId: accountId,
      currencyCode: 'EGP',
    );
    final mad = await repo.createPocket(
      accountId: accountId,
      currencyCode: 'MAD',
    );

    expect((await repo.listAccounts(workspaceId)).single.pockets.first.id, egp);
    await repo.markAccountUsedByPocket(mad);
    expect((await repo.listAccounts(workspaceId)).single.pockets.first.id, egp);
    await repo.setDefaultPocket(mad);
    final pockets = (await repo.listAccounts(workspaceId)).single.pockets;
    expect(pockets.first.id, mad);
    expect(pockets.first.isDefault, isTrue);
    expect(pockets.singleWhere((p) => p.id == egp).isDefault, isFalse);
  });

  test('InstaPay channel links to a bank', () async {
    final db = createTestAppDatabase();
    addTearDown(db.close);
    final repo = FinanceSetupRepository(await db.open());
    final workspaceId = await repo.workspaceId('فريلانس');
    final bankId = await repo.createAccount(
      workspaceId: workspaceId,
      name: 'البنك',
      type: 'bank',
    );
    final channelId = await repo.createChannel(
      workspaceId: workspaceId,
      name: 'InstaPay',
      type: 'instapay',
    );
    await repo.linkChannelToAccount(channelId: channelId, accountId: bankId);
    expect((await repo.listChannels(workspaceId)).single.details, 'البنك');
  });

  test('categories support safe parent hierarchy and rename', () async {
    final db = createTestAppDatabase();
    addTearDown(db.close);
    final repo = FinanceSetupRepository(await db.open());
    final workspaceId = await repo.createWorkspace(
      name: 'Hierarchy test',
      type: 'personal',
    );
    final parent = await repo.createCategory(
      workspaceId: workspaceId,
      name: 'Home',
      kind: 'expense',
    );
    final child = await repo.createCategory(
      workspaceId: workspaceId,
      name: 'Electricity',
      kind: 'expense',
      parentId: parent,
    );
    await repo.updateCategory(id: child, name: 'Power', parentId: parent);
    final item = (await repo.listCategories(
      workspaceId,
    )).singleWhere((e) => e.id == child);
    expect(item.parentId, parent);
    expect(item.displayName, 'Home › Power');
  });

  test('favorite and recently used accounts are listed first', () async {
    final db = createTestAppDatabase();
    addTearDown(db.close);
    final repo = FinanceSetupRepository(await db.open());
    final workspaceId = await repo.createWorkspace(
      name: 'Priority test',
      type: 'personal',
    );
    final rare = await repo.createAccount(
      workspaceId: workspaceId,
      name: 'A rare bank',
      type: 'bank',
    );
    final daily = await repo.createAccount(
      workspaceId: workspaceId,
      name: 'Z daily cash',
      type: 'cash',
    );
    final pocket = await repo.createPocket(
      accountId: daily,
      currencyCode: 'EGP',
    );
    await repo.markAccountUsedByPocket(pocket);
    expect((await repo.listAccounts(workspaceId)).first.id, daily);
    await repo.setAccountFavorite(rare, true);
    expect((await repo.listAccounts(workspaceId)).first.id, rare);
  });

  test('renaming an account preserves its pockets and balances', () async {
    final db = createTestAppDatabase();
    addTearDown(db.close);
    final database = await db.open();
    final repo = FinanceSetupRepository(database);
    final workspaceId = await repo.createWorkspace(
      name: 'Rename test',
      type: 'personal',
    );
    final accountId = await repo.createAccount(
      workspaceId: workspaceId,
      name: 'Old name',
      type: 'bank',
    );
    final pocketId = await repo.createPocket(
      accountId: accountId,
      currencyCode: 'EGP',
    );
    await repo.renameAccount(accountId, 'New name');
    final account = (await repo.listAccounts(workspaceId)).single;
    expect(account.name, 'New name');
    expect(account.pockets.single.id, pocketId);
  });
}
