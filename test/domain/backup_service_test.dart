import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/domain/backup/backup_service.dart';
import 'package:path/path.dart' as p;

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory docs;
  late TestEnv env;
  late BackupService backup;

  setUp(() async {
    root = await tempDir('hydra_backup_');
    docs = Directory(p.join(root.path, 'documents'));
    await docs.create(recursive: true);
    env = await TestEnv.file(dbPathIn(root));
    backup = BackupService(env.db, documentsDirectory: () async => docs);
  });

  tearDown(() async {
    await env.close();
    await cleanDir(root);
  });

  Future<void> addProduct(String name, String barcode) async {
    await env.products.create(
      Product(name: name, barcode: barcode, priceCentimes: 1000),
    );
  }

  test('creates a valid SQLite backup outside the live database', () async {
    await addProduct('Lait', '6111245100059');

    final info = await backup.createBackup();

    expect(await File(info.path).exists(), isTrue);
    expect(info.sizeBytes, greaterThan(4096));
    expect(info.path, contains('backups'));
    expect(info.path, endsWith('.db'));

    final header = await File(info.path).openRead(0, 16).first;
    expect(String.fromCharCodes(header), startsWith('SQLite format 3'));

    final listed = await backup.listBackups();
    expect(listed, hasLength(1));
    expect(listed.single.path, info.path);
  });

  test('restoring replaces the live data with the backup contents', () async {
    await addProduct('Lait', '6111245100059');
    final info = await backup.createBackup();

    await addProduct('Pain', '6111245100073');
    expect(await env.products.countActive(), 2);

    await backup.restoreBackup(info.path);

    expect(env.db.isOpen, isTrue);
    expect(await env.products.countActive(), 1);
    final restored = await env.products.findByBarcode('6111245100059');
    expect(restored, isNotNull);
    expect(await env.products.findByBarcode('6111245100073'), isNull);

    // Settings and shop survive as well.
    expect(await env.settings.shop(), isNotNull);
    expect(await env.settings.language(), 'ar');
  });

  test('rejects missing, tiny and non-SQLite files', () async {
    await expectLater(
      backup.restoreBackup(p.join(root.path, 'missing.db')),
      throwsA(isA<AppError>()),
    );

    final tiny = File(p.join(root.path, 'tiny.db'));
    await tiny.writeAsBytes(List.filled(100, 0));
    await expectLater(
      backup.restoreBackup(tiny.path),
      throwsA(isA<AppError>()),
    );

    final text = File(p.join(root.path, 'text.db'));
    await text.writeAsString('x' * 8192);
    await expectLater(
      backup.restoreBackup(text.path),
      throwsA(isA<AppError>()),
    );

    // The live database is still usable after rejected restores.
    expect(await env.products.countActive(), 0);
  });

  test('deletes a backup file safely', () async {
    await addProduct('Lait', '6111245100059');
    final info = await backup.createBackup();

    await backup.deleteBackup(info.path);
    expect(await File(info.path).exists(), isFalse);
    expect(await backup.listBackups(), isEmpty);

    // Deleting again (or a missing path) is a no-op.
    await backup.deleteBackup(info.path);
  });

  test('listBackups returns newest first and ignores other files', () async {
    await backup.listBackups();
    final dir = Directory(p.join(docs.path, 'backups'));
    await dir.create(recursive: true);

    final older = File(p.join(dir.path, 'hydra_pos_backup_20260101_100000.db'));
    final newer = File(p.join(dir.path, 'hydra_pos_backup_20260102_100000.db'));
    final other = File(p.join(dir.path, 'notes.txt'));
    await older.writeAsBytes(List.filled(5000, 0));
    await newer.writeAsBytes(List.filled(5000, 0));
    await other.writeAsString('ignore me');
    await older.setLastModified(DateTime(2026, 1, 1, 10));
    await newer.setLastModified(DateTime(2026, 1, 2, 10));

    final listed = await backup.listBackups();
    expect(listed.map((b) => p.basename(b.path)).toList(), [
      'hydra_pos_backup_20260102_100000.db',
      'hydra_pos_backup_20260101_100000.db',
    ]);
  });
}
