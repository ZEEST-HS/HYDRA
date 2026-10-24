import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../services/file_share_service.dart';
import '../../services/import_export_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});

  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  bool _updateStock = false;
  bool _updateExisting = true;
  bool _busy = false;
  String _busyLabel = '';

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
        });
      }
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt', 'xlsx', 'xls'],
    );
    final path = picked?.path;
    if (path == null || !mounted) return;
    await _run('Import', () async {
      final c = AppScope.of(context);
      final imported = await c.io.importProductsFile(
        path,
        updateStock: _updateStock,
        updateExisting: _updateExisting,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ImportResultDialog(result: imported),
      );
    });
  }

  Future<void> _template() async {
    await _run('Modèle CSV', () async {
      final c = AppScope.of(context);
      await const FileShareService().shareCsv(
        fileName: 'modele_produits.csv',
        csv: c.io.productTemplateCsv(),
        subject: c.l10n.t('Modèle CSV'),
      );
    });
  }

  Future<void> _exportProductsCsv() async {
    await _run('Export CSV', () async {
      final c = AppScope.of(context);
      final products = await c.products.all(limit: 10000);
      await const FileShareService().shareCsv(
        fileName: 'produits_${Dates.businessDate()}.csv',
        csv: c.io.exportProductsCsv(products),
        subject: c.l10n.t('Produits'),
      );
    });
  }

  Future<void> _exportProductsXlsx() async {
    await _run('Export Excel', () async {
      final c = AppScope.of(context);
      final products = await c.products.all(limit: 10000);
      await const FileShareService().shareBytes(
        fileName: 'produits_${Dates.businessDate()}.xlsx',
        bytes: c.io.exportProductsXlsx(products),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: c.l10n.t('Produits'),
      );
    });
  }

  Future<void> _exportSales() async {
    await _run('Export ventes', () async {
      final c = AppScope.of(context);
      await const FileShareService().shareCsv(
        fileName: 'ventes_${Dates.businessDate()}.csv',
        csv: await c.io.exportSalesCsv(),
        subject: c.l10n.t('Ventes'),
      );
    });
  }

  Future<void> _exportPurchases() async {
    await _run('Export achats', () async {
      final c = AppScope.of(context);
      await const FileShareService().shareCsv(
        fileName: 'achats_${Dates.businessDate()}.csv',
        csv: await c.io.exportPurchasesCsv(),
        subject: c.l10n.t('Achats'),
      );
    });
  }

  Future<void> _exportDebts({required bool customers}) async {
    await _run('Export dettes', () async {
      final c = AppScope.of(context);
      final csv = customers
          ? await c.io.exportCustomerDebtsCsv()
          : await c.io.exportSupplierDebtsCsv();
      await const FileShareService().shareCsv(
        fileName:
            '${customers ? 'dettes_clients' : 'dettes_fournisseurs'}_${Dates.businessDate()}.csv',
        csv: csv,
        subject: c.l10n.t(customers ? 'Dettes clients' : 'Dettes fournisseurs'),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Importer / Exporter')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: PageBody(
        maxWidth: 760,
        child: ListView(
          children: [
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(_busyLabel),
                  ],
                ),
              ),
            SectionTitle(l.t('Importer des produits')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.t(
                        'Format attendu : nom, code-barres, prix, coût, stock, unité, catégorie',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.t(
                        'Les prix et le stock locaux ne sont modifiés que par cet import explicite. Les ventes, achats et dettes ne sont jamais touchés.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.t('Mettre à jour les produits existants')),
                      value: _updateExisting,
                      onChanged: (value) =>
                          setState(() => _updateExisting = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.t('Mettre à jour le stock')),
                      subtitle: Text(
                        l.t(
                          'Le stock est un mouvement compté, pas un écrasement silencieux.',
                        ),
                      ),
                      value: _updateStock,
                      onChanged: (value) =>
                          setState(() => _updateStock = value),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.upload_file),
                      label: Text(l.t('Importer un fichier CSV ou Excel')),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _template,
                      icon: const Icon(Icons.download_outlined),
                      label: Text(l.t('Télécharger le modèle')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SectionTitle(l.t('Exporter')),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.table_view_outlined),
                    title: Text(l.t('Produits')),
                    subtitle: Text(l.t('Export CSV')),
                    trailing: const Icon(Icons.ios_share),
                    onTap: _busy ? null : _exportProductsCsv,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.grid_on_outlined),
                    title: Text(l.t('Produits')),
                    subtitle: Text(l.t('Export Excel')),
                    trailing: const Icon(Icons.ios_share),
                    onTap: _busy ? null : _exportProductsXlsx,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(l.t('Exporter les ventes')),
                    subtitle: Text(l.t('Toutes les ventes')),
                    trailing: const Icon(Icons.ios_share),
                    onTap: _busy ? null : _exportSales,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: Text(l.t('Achats')),
                    subtitle: Text(l.t('Tous les achats')),
                    trailing: const Icon(Icons.ios_share),
                    onTap: _busy ? null : _exportPurchases,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: Text(l.t('Dettes clients')),
                    subtitle: Text(l.t('Export CSV')),
                    trailing: const Icon(Icons.ios_share),
                    onTap: _busy ? null : () => _exportDebts(customers: true),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.store_outlined),
                    title: Text(l.t('Dettes fournisseurs')),
                    subtitle: Text(l.t('Export CSV')),
                    trailing: const Icon(Icons.ios_share),
                    onTap: _busy ? null : () => _exportDebts(customers: false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Card(
              color: AppTheme.primary.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l.t(
                          'Les fichiers sont partagés via le menu Android. Aucune donnée n\'est envoyée à un serveur.',
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
      ),
    );
  }
}

class _ImportResultDialog extends StatelessWidget {
  const _ImportResultDialog({required this.result});
  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(l.t('Import terminé')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${l.t('Créés')} : ${result.created}'),
              Text('${l.t('Mis à jour')} : ${result.updated}'),
              Text('${l.t('Lignes ignorées')} : ${result.skipped}'),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '${l.t('Erreurs')} : ${result.errors.length}',
                  style: TextStyle(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                for (final error in result.errors.take(12))
                  Text(
                    '${l.fill('Ligne {row}', {'row': error.row})} — ${error.message}',
                    style: TextStyle(fontSize: 12, color: AppTheme.danger),
                  ),
                if (result.errors.length > 12)
                  Text(
                    '…',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Fermer')),
        ),
      ],
    );
  }
}
