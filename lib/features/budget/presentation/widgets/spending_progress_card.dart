import 'package:flutter/material.dart';
import '../../../../core/theme/zad_tokens.dart';
import '../../../../core/widgets/zad_card.dart';
import '../../domain/budget_models.dart';

/// Lightweight spending progress: one bar, spent/remaining figures,
/// and a single contextual warning (worst condition wins).
class SpendingProgressCard extends StatelessWidget {
  final BudgetPlan plan;
  final BudgetSummary summary;

  const SpendingProgressCard({
    super.key,
    required this.plan,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final total = plan.totalMoney;
    final ratio = total > 0 ? (s.totalSpent / total).clamp(0.0, 1.0) : 1.0;
    // Finance semantics: green under 80%, amber near the limit, red over.
    // Bar fill uses the brighter gold for caution (Stitch secondary-container
    // bar); text stays in the darker readable warning amber.
    final caution = ratio >= 0.8;
    final barColor = s.remainingMoney < 0
        ? ZadTokens.danger
        : caution
        ? ZadTokens.gold
        : ZadTokens.primary;
    final todayColor = s.isOverDailyLimit
        ? ZadTokens.danger
        : (s.safeDailyLimit > 0 && s.todaySpending >= 0.8 * s.safeDailyLimit)
        ? ZadTokens.warning
        : ZadTokens.text;

    // One status line only — worst condition wins (Stitch: warning icon +
    // colored text row, no boxed banner).
    final String status;
    final Color statusColor;
    final IconData statusIcon;
    if (s.remainingMoney < 0) {
      status = 'تجاوزت الميزانية';
      statusColor = ZadTokens.danger;
      statusIcon = Icons.error_outline;
    } else if (s.isOverDailyLimit) {
      status = 'تجاوزت الحد اليومي — حاول تقليل مصاريف اليوم';
      statusColor = ZadTokens.danger;
      statusIcon = Icons.error_outline;
    } else if (s.daysRemaining == 0) {
      status = 'انتهت مدة هذه الخطة';
      statusColor = ZadTokens.warning;
      statusIcon = Icons.warning_amber_outlined;
    } else if (caution) {
      status = 'انتبه، اقتربت من الحد';
      statusColor = ZadTokens.warning;
      statusIcon = Icons.warning_amber_outlined;
    } else {
      status = 'الوضع جيد';
      statusColor = ZadTokens.primary;
      statusIcon = Icons.check_circle_outline;
    }

    return ZadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stitch: title + percentage headline row.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'استهلاك الميزانية',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${(ratio * 100).round()}%',
                // Muted like Stitch; state color lives in the bar + status.
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: ZadTokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZadTokens.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'المصروف',
                style: TextStyle(color: ZadTokens.textMuted, fontSize: 13),
              ),
              Text(
                '${s.totalSpent.toStringAsFixed(2)} / ${total.toStringAsFixed(2)} MRU',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZadTokens.s2),
          ClipRRect(
            // Fully rounded thick bar on a cream track (Stitch).
            borderRadius: BorderRadius.circular(999),
            // Bar fills 0 → ratio once on load; retargets smoothly on data
            // change. Value is display-only, calculations untouched.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 12,
                color: barColor,
                backgroundColor: ZadTokens.surfaceContainer,
              ),
            ),
          ),
          const SizedBox(height: ZadTokens.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'مصروف اليوم',
                style: TextStyle(color: ZadTokens.textMuted, fontSize: 13),
              ),
              Text(
                '${s.todaySpending.toStringAsFixed(2)} MRU',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: todayColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZadTokens.s3),
          Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: ZadTokens.s2),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
