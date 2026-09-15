import 'package:al_hesab/app/app.dart';
import 'package:al_hesab/core/database/app_database.dart';
import 'package:al_hesab/core/database/database_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase testDatabase;
  setUpAll(sqfliteFfiInit);
  setUp(
    () => testDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      pathProvider: () async => inMemoryDatabasePath,
    ),
  );
  tearDown(() => testDatabase.close());

  test('database enables foreign keys and initializes once', () async {
    final database = await testDatabase.open();
    final foreignKeys = await database.rawQuery('PRAGMA foreign_keys');
    final metadata = await database.query('app_metadata');
    expect(foreignKeys.single.values.single, 1);
    expect(metadata, hasLength(2));
  });

  testWidgets('app renders its Arabic RTL setup dashboard', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(testDatabase)],
        child: const AlHesabApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('عَ الحساب'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('التقارير'), findsOneWidget);
    expect(find.text('ميزانية'), findsOneWidget);
    expect(
      tester.widget<Directionality>(find.byType(Directionality)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('core shell supports a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(testDatabase)],
        child: const AlHesabApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('حركة'), findsOneWidget);
  });
}
