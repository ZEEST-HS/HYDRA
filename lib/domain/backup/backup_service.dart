import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/db/app_database.dart';
import '../../core/errors.dart';

class BackupInfo {
  const BackupInfo({
    required this.path,
    required this.sizeBytes,
    required this.createdAt,
  });
  final String path;
  final int sizeBytes;
  final DateTime createdAt;
}

class BackupService {
  BackupService(this.appDb, {Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final AppDatabase appDb;
  final Future<Directory> Function() _documentsDirectory;
  bool _busy = false;

  Future<BackupInfo> createBackup() async {
    if (_busy) throw ConflictError('Une sauvegarde est déjà en cours.');
    _busy = true;
    try {
      final dbPath = appDb.path;
      if (dbPath == null) throw AppError('backup', 'Base de données fermée.');
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw AppError('backup', 'Fichier de base de données introuvable.');
      }
      await appDb.checkpoint();
      final docs = await _documentsDirectory();
      final dir = Directory(p.join(docs.path, 'backups'));
      await dir.create(recursive: true);
      final now = DateTime.now();
      final name =
          'hydra_pos_backup_'
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.db';
      final target = File(p.join(dir.path, name));

      // Copy while the database is closed so no write can interleave.
      await appDb.close();
      try {
        await dbFile.copy(target.path);
      } finally {
        await appDb.open();
      }
      final length = await target.length();
      return BackupInfo(path: target.path, sizeBytes: length, createdAt: now);
    } finally {
      _busy = false;
    }
  }

  Future<List<BackupInfo>> listBackups() async {
    final docs = await _documentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) return const [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.db'))
        .cast<File>()
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files
        .map(
          (f) => BackupInfo(
            path: f.path,
            sizeBytes: f.statSync().size,
            createdAt: f.statSync().modified,
          ),
        )
        .toList();
  }

  /// Validates the SQLite header and essential tables before replacing data.
  Future<void> restoreBackup(String backupPath) async {
    if (_busy) throw ConflictError('Une opération de sauvegarde est en cours.');
    final backup = File(backupPath);
    if (!await backup.exists()) {
      throw AppError('backup', 'Fichier de sauvegarde introuvable.');
    }
    final length = await backup.length();
    if (length < 4096) {
      throw AppError('backup', 'Fichier de sauvegarde invalide (trop petit).');
    }
    final header = await backup.openRead(0, 16).first;
    final headerText = String.fromCharCodes(header);
    if (!headerText.startsWith('SQLite format 3')) {
      throw AppError('backup', 'Ce fichier n\'est pas une base SQLite valide.');
    }
    await _validateSqlite(backupPath);

    _busy = true;
    String? safetyCopy;
    try {
      final dbPath = appDb.path;
      if (dbPath == null) throw AppError('backup', 'Base de données fermée.');
      final current = File(dbPath);
      await appDb.checkpoint();
      await appDb.close();
      try {
        if (await current.exists()) {
          safetyCopy = '$dbPath.pre_restore';
          await current.copy(safetyCopy);
        }
        await backup.copy(dbPath);
        await appDb.open();
        // Force a schema check and a simple read after opening.
        await appDb.count('products');
      } catch (e) {
        await appDb.close();
        if (safetyCopy != null && await File(safetyCopy).exists()) {
          await File(safetyCopy).copy(dbPath);
        }
        await appDb.open();
        throw AppError('backup', 'Restauration échouée: $e');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _validateSqlite(String path) async {
    final factory = appDb.db.isOpen ? appDb.db : null;
    if (factory == null) {
      throw AppError('backup', 'Base de données fermée.');
    }
    // Validate using a temporary in-memory attach so the live DB is untouched.
    try {
      await factory.execute('ATTACH DATABASE ? AS backup_check', [path]);
      final check = await factory.rawQuery(
        'PRAGMA backup_check.integrity_check',
      );
      final tables = await factory.rawQuery(
        "SELECT name FROM backup_check.sqlite_master WHERE type = 'table'",
      );
      await factory.execute('DETACH DATABASE backup_check');
      final ok =
          check.isNotEmpty &&
          check.first.values.first?.toString().toLowerCase() == 'ok';
      if (!ok) {
        throw AppError('backup', 'La sauvegarde est corrompue.');
      }
      final names = tables.map((r) => r['name'].toString()).toSet();
      for (final required in ['products', 'sales', 'settings', 'shop']) {
        if (!names.contains(required)) {
          throw AppError(
            'backup',
            'La sauvegarde ne contient pas la table « $required ».',
          );
        }
      }
    } catch (e) {
      try {
        await factory.execute('DETACH DATABASE backup_check');
      } catch (_) {}
      if (e is AppError) rethrow;
      throw AppError('backup', 'Sauvegarde illisible: $e');
    }
  }

  Future<void> deleteBackup(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
