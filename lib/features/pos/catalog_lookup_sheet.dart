import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../domain/catalog/catalog_service.dart';
import '../../ui/theme.dart';

class CatalogSheetResult {
  const CatalogSheetResult.create(this.candidate) : createManually = false;
  const CatalogSheetResult.manual() : candidate = null, createManually = true;

  final CatalogCandidate? candidate;
  final bool createManually;
}

/// Looks up a barcode in Open Food Facts / Open Products Facts. It only
/// returns data to the form: prices, stock and debts are never touched.
class CatalogLookupSheet extends StatefulWidget {
  const CatalogLookupSheet({super.key, required this.barcode});
  final String barcode;

  @override
  State<CatalogLookupSheet> createState() => _CatalogLookupSheetState();
}

class _CatalogLookupSheetState extends State<CatalogLookupSheet> {
  CatalogLookupResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup({bool force = false}) async {
    final c = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final enabled = await c.settings.catalogEnabled();
      if (!enabled) {
        if (mounted) {
          setState(() {
            _loading = false;
            _result = const CatalogLookupResult(
              message: 'La recherche en ligne est désactivée.',
            );
          });
        }
        return;
      }
      final result = await c.catalog.lookup(
        widget.barcode,
        forceRefresh: force,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.t('Recherche en ligne'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              widget.barcode,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.danger),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _lookup(force: true),
                child: Text(l.t('Réessayer')),
              ),
            ] else
              _body(context, l),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, L10n l) {
    final result = _result;
    final candidate = result?.candidate;
    if (candidate != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (candidate.imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            candidate.imageUrl!,
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 76,
                              height: 76,
                              child: Icon(Icons.image_not_supported_outlined),
                            ),
                          ),
                        ),
                      if (candidate.imageUrl != null) const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (candidate.brand != null)
                              Text(
                                candidate.brand!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            if (candidate.quantityText != null)
                              Text(
                                candidate.quantityText!,
                                style: const TextStyle(fontSize: 12),
                              ),
                            if (candidate.category != null)
                              Text(
                                candidate.category!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l.t(
                              'Données externes — vérifiez le prix et le stock',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l.t('Source externe')} : '
                    '${result?.providerName ?? candidate.source}'
                    '${result?.fromCache == true ? ' (cache)' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, CatalogSheetResult.create(candidate)),
            icon: const Icon(Icons.download_done),
            label: Text(l.t('Utiliser ces informations')),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.t('Saisie manuelle')),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          result?.offline == true ? Icons.wifi_off : Icons.search_off,
          size: 46,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 10),
        Text(
          result?.offline == true
              ? l.t('Non disponible hors ligne')
              : l.t('Aucun produit trouvé en ligne'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (result?.message != null) ...[
          const SizedBox(height: 6),
          Text(
            result!.message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () =>
              Navigator.pop(context, const CatalogSheetResult.manual()),
          icon: const Icon(Icons.add),
          label: Text(l.t('Créer un produit avec ce code')),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _lookup(force: true),
          icon: const Icon(Icons.refresh),
          label: Text(l.t('Réessayer')),
        ),
        const SizedBox(height: 10),
        Text(
          l.t(
            'Recherche locale d\'abord, puis en ligne. Les prix et le stock locaux ne sont jamais écrasés.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
