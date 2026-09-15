import 'dart:io';

import 'package:al_hesab/core/database/app_database.dart';
import 'package:al_hesab/features/setup/data/finance_setup_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('backup restores a consistent earlier database state', () async {
    final directory = await Directory.systemTemp.createTemp('al_hesab_backup_');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'app.db');
    final appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      pathProvider: () async => path,
    );
    addTearDown(appDatabase.close);
    var repo = FinanceSetupRepository(await appDatabase.open());
    final beforeId = await repo.createWorkspace(
      name: 'قبل النسخة',
      type: 'other',
    );

    final backup = await appDatabase.createBackup();
    repo = FinanceSetupRepository(await appDatabase.open());
    await repo.createWorkspace(name: 'بعد النسخة', type: 'other');
    expect(await repo.workspaceId('بعد النسخة'), isPositive);

    await appDatabase.restoreBackup(backup.path);
    repo = FinanceSetupRepository(await appDatabase.open());
    expect(await repo.workspaceId('قبل النسخة'), beforeId);
    await expectLater(() => repo.workspaceId('بعد النسخة'), throwsStateError);
    expect(await appDatabase.listBackups(), hasLength(1));
  });

  test(
    'corrupt managed backup is rejected without changing current data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'al_hesab_corrupt_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'app.db');
      final appDatabase = AppDatabase(
        factory: databaseFactoryFfi,
        pathProvider: () async => path,
      );
      addTearDown(appDatabase.close);
      final repo = FinanceSetupRepository(await appDatabase.open());
      final workspaceId = await repo.createWorkspace(
        name: 'بيانات سليمة',
        type: 'other',
      );
      final backup = await appDatabase.createBackup();
      final corrupt = File(p.join(p.dirname(backup.path), 'corrupt.db'));
      await corrupt.writeAsString('not a sqlite database');

      await expectLater(
        () => appDatabase.restoreBackup(corrupt.path),
        throwsA(anything),
      );
      final current = FinanceSetupRepository(await appDatabase.open());
      expect(await current.workspaceId('بيانات سليمة'), workspaceId);
    },
  );

  test('restore refuses files outside the managed backup directory', () async {
    final directory = await Directory.systemTemp.createTemp('al_hesab_scope_');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'app.db');
    final appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      pathProvider: () async => path,
    );
    addTearDown(appDatabase.close);
    await appDatabase.open();
    final outside = File(p.join(directory.path, 'outside.db'));
    await outside.writeAsString('anything');
    await expectLater(
      () => appDatabase.restoreBackup(outside.path),
      throwsArgumentError,
    );
  });
}
