import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes a generated file to a temporary directory and opens the platform
/// share sheet. Works for PDFs and CSV exports.
class FileShareService {
  const FileShareService();

  Future<String> writeTemp({
    required String fileName,
    required List<int> bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, 'exports'));
    await folder.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File(p.join(folder.path, safeName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> shareBytes({
    required String fileName,
    required List<int> bytes,
    required String mimeType,
    String? subject,
    String? text,
  }) async {
    final path = await writeTemp(fileName: fileName, bytes: bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType, name: fileName)],
        subject: subject,
        text: text,
        title: subject,
      ),
    );
  }

  Future<void> shareCsv({
    required String fileName,
    required String csv,
    String? subject,
  }) async {
    await shareBytes(
      fileName: fileName,
      bytes: utf8.encode(csv),
      mimeType: 'text/csv',
      subject: subject,
      text: subject,
    );
  }

  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
