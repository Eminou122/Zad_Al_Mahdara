import 'package:flutter/material.dart';
import '../../../../core/theme/zad_tokens.dart';
import '../../../../core/widgets/zad_card.dart';
import '../../domain/budget_models.dart';

/// Daily-purchases breakdown: planned vs. actually-purchased vs. saved
/// (Gate 17), plus the list of active recurring purchases with today's
/// mark status when known. Display-only — does not affect budget math.
class RecurringPurchasesCard extends StatelessWidget {
  final RecurringPurchaseOverview? stats;
  final List<RecurringPurchase> items;
  final List<TodayRecurringPurchase> todayItems;
  final VoidCallback onManage;

  const RecurringPurchasesCard({
    super.key,
    required this.stats,
    required this.items,
    required this.todayItems,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ZadCard(
        child: Column(
          children: [
            const Icon(
              Icons.shopping_basket_outlined,
              size: 32,
              color: ZadTokens.textMuted,
            ),
            const SizedBox(height: ZadTokens.s2),
            const Text(
              'لا توجد مشتريات يومية متكررة بعد',
              style: TextStyle(color: ZadTokens.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ZadTokens.s3),
            ElevatedButton(
              onPressed: onManage,
              child: const Text('إدارة المشتريات المتكررة'),
            ),
          ],
        ),
      );
    }

    final s = stats;
    final saved = s == null
        ? 0.0
        : (s.plannedTotal - s.actualPurchasedTotal).clamp(0.0, double.infinity);
    final statusById = {
      for (final t in todayItems) t.recurringPurchaseId: t.status,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s != null)
          ZadCard(
            margin: const EdgeInsets.only(bottom: ZadTokens.s2),
            child: Column(
              children: [
                _statRow('المتوقع لهذه الفترة', s.plannedTotal),
                _statRow(
                  'تم شراؤه فعلاً',
                  s.actualPurchasedTotal,
                  color: ZadTokens.primary,
                ),
                _statRow(
                  'الموفَّر (غير مشترى)',
                  saved,
                  color: ZadTokens.textMuted,
                ),
              ],
            ),
          ),
        for (final item in items)
          ZadCard(
            margin: const EdgeInsets.only(bottom: ZadTokens.s2),
            padding: const EdgeInsets.symmetric(
              horizontal: ZadTokens.s4,
              vertical: ZadTokens.s3,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ZadTokens.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.shopping_basket_outlined,
                    color: ZadTokens.goldDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: ZadTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _freqLabel(item) +
                            (statusById[item.id] == null
                                ? ''
                                : '  •  ${_statusText(statusById[item.id]!)}'),
                        style: TextStyle(
                          fontSize: 12,
                          color: statusById[item.id] == null
                              ? ZadTokens.textMuted
                              : _statusColor(statusById[item.id]!),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ZadTokens.s2),
                Text(
                  '${item.price.toStringAsFixed(2)} MRU',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ZadTokens.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Widget _statRow(String label, double value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: ZadTokens.s1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: ZadTokens.textMuted),
          ),
        ),
        Text(
          '${value.toStringAsFixed(2)} MRU',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color,
          ),
        ),
      ],
    ),
  );

  static String _freqLabel(RecurringPurchase item) {
    if (item.frequency == 'daily') return 'كل يوم';
    if (item.frequency == 'weekly') return 'كل أسبوع';
    return 'كل ${item.intervalDays ?? 2} أيام';
  }

  static String _statusText(String status) {
    if (status == 'purchased') return 'تم الشراء اليوم';
    if (status == 'skipped') return 'تم تخطيه اليوم';
    return 'بانتظار اليوم';
  }

  static Color _statusColor(String status) {
    if (status == 'purchased') return ZadTokens.primary;
    if (status == 'skipped') return ZadTokens.textMuted;
    return ZadTokens.warning;
  }
}
