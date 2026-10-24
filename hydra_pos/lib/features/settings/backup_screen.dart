import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../domain/backup/backup_service.dart';
import '../../services/file_share_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  Future<List<BackupInfo>>? _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<BackupInfo>> _load() =>
      AppScope.read(context).backup.listBackups();

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _create() async {
    final c = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final info = await c.backup.createBackup();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(c.l10n.t('Sauvegarde créée')),
          content: SelectableText(
            '${c.l10n.t('Fichier')} :\n${info.path}\n\n'
            '${(info.sizeBytes / 1024).toStringAsFixed(1)} KB',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(c.l10n.t('Fermer')),
            ),
          ],
        ),
      );
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(String path) async {
    final c = AppScope.of(context);
    final l = c.l10n;
    final ok = await confirm(
      context,
      title: l.t('Restaurer cette sauvegarde ?'),
      message: l.t('Les données actuelles seront remplacées.'),
      confirmLabel: l.t('Restaurer'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await c.backup.restoreBackup(path);
      await c.reloadShop();
      if (!mounted) return;
      showInfo(context, l.t('Sauvegarde restaurée'));
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickExternal() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    if (path == null || !mounted) return;
    await _restore(path);
  }

  Future<void> _share(BackupInfo info) async {
    try {
      final bytes = await File(info.path).readAsBytes();
      await const FileShareService().shareBytes(
        fileName: info.path.split(Platform.pathSeparator).last,
        bytes: bytes,
        mimeType: 'application/x-sqlite3',
        subject: 'Hydra POS backup',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(BackupInfo info) async {
    final l = AppScope.of(context).l10n;
    final ok = await confirm(
      context,
      title: l.t('Supprimer cette sauvegarde ?'),
      confirmLabel: l.t('Supprimer'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.of(context).backup.deleteBackup(info.path);
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Sauvegarde')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: FutureBuilder<List<BackupInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              message: snapshot.error.toString(),
              icon: Icons.error_outline,
              action: FilledButton(
                onPressed: _reload,
                child: Text(l.t('Réessayer')),
              ),
            );
          }
          final backups = snapshot.data ?? const <BackupInfo>[];
          return PageBody(
            maxWidth: 760,
            child: ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.t('Sauvegarder la base'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l.t(
                            'La sauvegarde copie la base SQLite locale sur cet appareil.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _busy ? null : _create,
                          icon: const Icon(Icons.backup_outlined),
                          label: Text(l.t('Créer une sauvegarde')),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pickExternal,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text(l.t('Restaurer un fichier externe')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SectionTitle(l.t('Sauvegardes locales')),
                if (backups.isEmpty)
                  Card(
                    child: EmptyState(
                      message: l.t('Aucune sauvegarde'),
                      icon: Icons.inventory_2_outlined,
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final backup in backups)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(
                                alpha: 0.1,
                              ),
                              child: Icon(
                                Icons.archive_outlined,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              backup.path.split(Platform.pathSeparator).last,
                            ),
                            subtitle: Text(
                              '${Dates.formatDateTime(backup.createdAt)} · '
                              '${(backup.sizeBytes / 1024).toStringAsFixed(1)} KB',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'restore') _restore(backup.path);
                                if (value == 'share') _share(backup);
                                if (value == 'delete') _delete(backup);
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'restore',
                                  child: Text(l.t('Restaurer')),
                                ),
                                PopupMenuItem(
                                  value: 'share',
                                  child: Text(l.t('Partager')),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(l.t('Supprimer')),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                Card(
                  color: AppTheme.danger.withValues(alpha: 0.06),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber, color: AppTheme.danger),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.t(
                              'La restauration remplace toutes les données actuelles. Une copie de sécurité est créée automatiquement.',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}
