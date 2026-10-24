import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../core/quantity.dart';
import '../theme.dart';

String money(int centimes, BuildContext context) =>
    Money.withCurrency(centimes, 'DH');

String qty(int milli, BuildContext context) => Qty.format(milli);

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.maxWidth = 1400,
  });

  final Widget child;
  final EdgeInsets padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.padding});
  final String text;
  final Widget? action;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(0, 8, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.footnote,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 18, color: tint),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  style: AppTheme.numberStyle.copyWith(
                    fontSize: 22,
                    color: tint,
                  ),
                ),
              ),
              if (footnote != null) ...[
                const SizedBox(height: 4),
                Text(
                  footnote!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 15,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String paymentLabel(String method, L10n l) {
  switch (method) {
    case 'cash':
      return l.t('Espèces');
    case 'card':
      return l.t('Carte bancaire');
    case 'cheque':
      return l.t('Chèque');
    case 'transfer':
      return l.t('Virement');
    case 'credit':
      return l.t('Crédit');
    default:
      return method;
  }
}

void showError(BuildContext context, Object error) {
  if (!context.mounted) return;
  final message = error is Exception ? error.toString() : error.toString();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
  );
}

void showInfo(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final l = L10n.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppTheme.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? l.t('Confirmer')),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  bool required = true,
  int maxLines = 1,
}) async {
  final l = L10n.of(context);
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
          validator: required
              ? (v) =>
                    (v == null || v.trim().isEmpty) ? l.t('Champ requis') : null
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(ctx, controller.text.trim());
            }
          },
          child: Text(l.t('Valider')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

String dateLabel(String businessDate, L10n l) {
  final date = Dates.tryParseDate(businessDate);
  return date == null ? businessDate : Dates.formatDate(date);
}

class AsyncBuilder<T> extends StatelessWidget {
  const AsyncBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.empty,
    this.loading,
  });

  final Future<T> future;
  final Widget Function(T data) builder;
  final Widget? empty;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return loading ?? const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            message: snapshot.error.toString(),
            icon: Icons.error_outline,
          );
        }
        final data = snapshot.data;
        if (data == null) return empty ?? const SizedBox.shrink();
        if (data is Iterable && data.isEmpty) {
          return empty ?? const SizedBox.shrink();
        }
        return builder(data);
      },
    );
  }
}

String stockLabel(int stockMilli, String baseUnit, L10n l) {
  final unit = unitLabel(baseUnit, l);
  return '${Qty.format(stockMilli)} $unit';
}

String unitLabel(String code, L10n l) {
  switch (code) {
    case 'piece':
      return l.t('Pièce');
    case 'kg':
      return l.t('Kg');
    case 'g':
      return 'g';
    case 'l':
      return l.t('Litre');
    case 'ml':
      return 'ml';
    default:
      return code;
  }
}

int stockColor(int stock, int minStock) {
  if (stock <= 0) return 0xFFB91C1C;
  if (minStock > 0 && stock <= minStock) return 0xFFD97706;
  return 0xFF15803D;
}
