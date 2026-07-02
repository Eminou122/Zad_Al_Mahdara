import 'package:flutter/material.dart';
import '../../../../core/theme/zad_tokens.dart';
import '../../../../core/widgets/zad_card.dart';
import '../../domain/budget_models.dart';
import 'budget_metric_tile.dart';

/// Dashboard hero card: remaining money + key metrics, or an empty state
/// with an inline setup action when no budget plan exists.
class BudgetSummaryCard extends StatelessWidget {
  final BudgetPlan? plan;
  final BudgetSummary? summary;
  final VoidCallback onSetup;

  const BudgetSummaryCard({
    super.key,
    required this.plan,
    required this.summary,
    required this.onSetup,
  });

  @override
  Widget build(BuildContext context) {
    if (plan == null || summary == null) {
      return ZadCard(
        highlighted: true,
        child: Column(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 40, color: ZadTokens.gold),
            const SizedBox(height: ZadTokens.s2),
            Text('لا توجد خطة ميزانية بعد',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: ZadTokens.s1),
            const Text(
              'أنشئ خطة ميزانية لتعرف كم بقي من مالك وكم تصرف كل يوم بأمان.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ZadTokens.textMuted, fontSize: 13),
            ),
            const SizedBox(height: ZadTokens.s4),
            ElevatedButton(
              onPressed: onSetup,
              child: const Text('إعداد الميزانية'),
            ),
          ],
        ),
      );
    }

    final p = plan!;
    final s = summary!;
    final safeLimit = s.safeDailyLimit < 0 ? 0.0 : s.safeDailyLimit;
    // Finance semantics: green = safe, amber = caution, red = danger.
    final remainingColor = s.remainingMoney < 0
        ? ZadTokens.danger
        : (p.totalMoney > 0 && s.remainingMoney / p.totalMoney <= 0.15)
            ? ZadTokens.warning
            : ZadTokens.primary;
    final daysColor = s.daysRemaining == 0
        ? ZadTokens.danger
        : s.daysRemaining <= 3
            ? ZadTokens.warning
            : ZadTokens.primary;
    final limitColor = (s.remainingMoney <= 0 || safeLimit <= 0)
        ? ZadTokens.danger
        : ZadTokens.primary;

    return ZadCard(
      highlighted: true,
      child: Column(
        children: [
          const Text('المال المتبقي',
              style: TextStyle(color: ZadTokens.textMuted, fontSize: 13)),
          const SizedBox(height: ZadTokens.s1),
          Text(
            '${s.remainingMoney.toStringAsFixed(2)} MRU',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: remainingColor,
            ),
          ),
          const SizedBox(height: ZadTokens.s3),
          const Divider(height: 1),
          const SizedBox(height: ZadTokens.s3),
          Row(
            children: [
              Expanded(
                child: BudgetMetricTile(
                  icon: Icons.savings_outlined,
                  value: p.totalMoney.toStringAsFixed(0),
                  label: 'إجمالي الميزانية',
                ),
              ),
              Expanded(
                child: BudgetMetricTile(
                  icon: Icons.calendar_month_outlined,
                  value: '${s.daysRemaining} / ${s.daysTotal}',
                  label: 'الأيام المتبقية',
                  valueColor: daysColor,
                ),
              ),
              Expanded(
                child: BudgetMetricTile(
                  icon: Icons.shield_outlined,
                  value: safeLimit.toStringAsFixed(0),
                  label: 'الحد اليومي الآمن',
                  valueColor: limitColor,
                ),
              ),
            ],
          ),
          if (p.note != null && p.note!.isNotEmpty) ...[
            const SizedBox(height: ZadTokens.s3),
            Text(
              p.note!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
