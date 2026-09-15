import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_migrations.dart';
import 'schema_v1.dart';

typedef DatabasePathProvider = Future<String> Function();

class LocalBackup {
  const LocalBackup({
    required this.path,
    required this.createdAt,
    required this.sizeBytes,
  });
  final String path;
  final DateTime createdAt;
  final int sizeBytes;
  String get name => p.basename(path);
}

class AppDatabase {
  AppDatabase({DatabaseFactory? factory, DatabasePathProvider? pathProvider})
    : _factory = factory ?? databaseFactory,
      _pathProvider = pathProvider ?? _defaultPath;

  static const schemaVersion = 4;
  static const databaseName = 'app.db';

  final DatabaseFactory _factory;
  final DatabasePathProvider _pathProvider;
  Database? _database;

  Future<Database> open() async {
    final current = _database;
    if (current != null && current.isOpen) return current;

    final path = await _pathProvider();
    _database = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createLatest,
        onUpgrade: _migrate,
      ),
    );
    return _database!;
  }

  Future<void> close() async {
    final current = _database;
    if (current != null && current.isOpen) await current.close();
    _database = null;
  }

  Future<List<LocalBackup>> listBackups() async {
    final directory = Directory(await _backupDirectory());
    if (!await directory.exists()) return const [];
    final backups = <LocalBackup>[];
    await for (final entity in directory.list()) {
      if (entity is File && p.extension(entity.path) == '.db') {
        final stat = await entity.stat();
        backups.add(
          LocalBackup(
            path: entity.path,
            createdAt: stat.modified,
            sizeBytes: stat.size,
          ),
        );
      }
    }
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  Future<LocalBackup> createBackup() async {
    final sourcePath = await _pathProvider();
    if (sourcePath == inMemoryDatabasePath) {
      throw UnsupportedError('In-memory databases cannot be backed up.');
    }
    final database = await open();
    await database.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final directory = Directory(await _backupDirectory());
    await directory.create(recursive: true);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final destination = p.join(directory.path, 'al-hesab-$stamp.db');
    await File(sourcePath).copy(destination);
    final stat = await File(destination).stat();
    return LocalBackup(
      path: destination,
      createdAt: stat.modified,
      sizeBytes: stat.size,
    );
  }

  Future<void> restoreBackup(String backupPath) async {
    final directory = p.normalize(p.absolute(await _backupDirectory()));
    final candidate = p.normalize(p.absolute(backupPath));
    if (!p.isWithin(directory, candidate) || !await File(candidate).exists()) {
      throw ArgumentError('Backup must be an existing managed local backup.');
    }
    await _validateBackup(candidate);
    final target = await _pathProvider();
    if (target == inMemoryDatabasePath) {
      throw UnsupportedError('In-memory databases cannot be restored.');
    }
    await close();
    final safety = '$target.before-restore';
    final targetFile = File(target);
    if (await targetFile.exists()) await targetFile.copy(safety);
    try {
      await File(candidate).copy(target);
      await open();
    } catch (_) {
      await close();
      if (await File(safety).exists()) await File(safety).copy(target);
      await open();
      rethrow;
    } finally {
      final safetyFile = File(safety);
      if (await safetyFile.exists()) await safetyFile.delete();
    }
  }

  Future<void> _validateBackup(String path) async {
    final candidate = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final integrity = await candidate.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.single.values.single != 'ok') {
        throw const FormatException('Backup database failed integrity check.');
      }
      final metadata = await candidate.query(
        'app_metadata',
        where: 'key = ?',
        whereArgs: ['schema_version'],
        limit: 1,
      );
      final backupVersion = int.tryParse('${metadata.singleOrNull?['value']}');
      if (backupVersion == null ||
          backupVersion < 1 ||
          backupVersion > schemaVersion) {
        throw const FormatException('Unsupported backup schema version.');
      }
    } finally {
      await candidate.close();
    }
  }

  Future<String> _backupDirectory() async {
    final databasePath = await _pathProvider();
    return p.join(p.dirname(databasePath), 'al_hesab_backups');
  }

  static Future<String> _defaultPath() async {
    return p.join(await getDatabasesPath(), databaseName);
  }

  static Future<void> _createLatest(Database db, int version) async {
    await SchemaV1.create(db, DateTime.now());
    if (version > 1) await DatabaseMigrations.migrate(db, 1, version);
  }

  static Future<void> _migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await DatabaseMigrations.migrate(db, oldVersion, newVersion);
  }
}
