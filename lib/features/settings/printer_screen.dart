import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  Future<_PrinterData>? _future;
  String _savedMac = '';
  String _savedName = '';
  int _paperWidth = 58;
  bool _autoPrint = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PrinterData> _load() async {
    final c = AppScope.read(context);
    _savedMac = await c.settings.printerMac();
    _savedName = await c.settings.printerName();
    _paperWidth = await c.settings.paperWidth();
    _autoPrint = await c.settings.autoPrint();
    String? error;
    var printers = const <BluetoothInfo>[];
    try {
      printers = await c.printer.pairedPrinters();
    } catch (e) {
      error = e.toString();
    }
    return _PrinterData(printers, error);
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _connect(BluetoothInfo printer) async {
    final c = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await c.printer.connect(printer.macAdress);
      await c.settings.savePrinter(mac: printer.macAdress, name: printer.name);
      if (!mounted) return;
      setState(() {
        _savedMac = printer.macAdress;
        _savedName = printer.name;
      });
      showInfo(context, '${c.l10n.t('Connecter')} : ${printer.name}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    final c = AppScope.of(context);
    if (_savedMac.isEmpty) {
      showError(context, c.l10n.t('Sélectionnez une imprimante.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await c.printer.testPrinter();
      if (mounted) showInfo(context, c.l10n.t('Test envoyé.'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPaper(int width) async {
    await AppScope.of(context).settings.set('paper_width', '$width');
    if (mounted) setState(() => _paperWidth = width);
  }

  Future<void> _setAutoPrint(bool value) async {
    await AppScope.of(context).settings.setBool('auto_print', value);
    if (mounted) setState(() => _autoPrint = value);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Imprimante Bluetooth')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: FutureBuilder<_PrinterData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
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
                          _savedName.isEmpty
                              ? l.t('Aucune imprimante sélectionnée')
                              : _savedName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_savedMac.isNotEmpty)
                          Text(
                            _savedMac,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _test,
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: Text(l.t('Tester l\'imprimante')),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _reload,
                              icon: const Icon(Icons.refresh),
                              label: Text(l.t('Actualiser')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.t(
                              'L\'impression thermique utilise l\'ASCII. Les accents et l\'arabe peuvent être remplacés. Utilisez le PDF pour un document complet.',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SectionTitle(l.t('Appareils appairés')),
                if (data?.error != null)
                  Card(
                    child: EmptyState(
                      message: data!.error!,
                      icon: Icons.bluetooth_disabled,
                      action: OutlinedButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: Text(l.t('Réessayer')),
                      ),
                    ),
                  )
                else if (data == null || data.printers.isEmpty)
                  Card(
                    child: EmptyState(
                      message: l.t('Aucune imprimante appairée'),
                      icon: Icons.print_disabled_outlined,
                      action: OutlinedButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: Text(l.t('Actualiser')),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final printer in data.printers)
                          ListTile(
                            leading: const Icon(Icons.print_outlined),
                            title: Text(printer.name),
                            subtitle: Text(printer.macAdress),
                            trailing: printer.macAdress == _savedMac
                                ? Icon(
                                    Icons.check_circle,
                                    color: AppTheme.success,
                                  )
                                : OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _connect(printer),
                                    child: Text(l.t('Connecter')),
                                  ),
                            onTap: _busy ? null : () => _connect(printer),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                SectionTitle(l.t('Options')),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(l.t('Format du papier')),
                        subtitle: Text('$_paperWidth mm'),
                        trailing: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 58, label: Text('58 mm')),
                            ButtonSegment(value: 80, label: Text('80 mm')),
                          ],
                          selected: {_paperWidth},
                          onSelectionChanged: (value) => _setPaper(value.first),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: Text(l.t('Impression automatique')),
                        subtitle: Text(l.t('Après chaque vente')),
                        value: _autoPrint,
                        onChanged: _setAutoPrint,
                      ),
                    ],
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

class _PrinterData {
  const _PrinterData(this.printers, this.error);
  final List<BluetoothInfo> printers;
  final String? error;
}
