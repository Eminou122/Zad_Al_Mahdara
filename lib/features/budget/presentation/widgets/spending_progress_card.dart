import 'package:flutter/material.dart';
import '../../../../core/theme/zad_tokens.dart';
import '../../../../core/widgets/zad_card.dart';
import '../../../../core/widgets/zad_info_banner.dart';
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
    final barColor = s.remainingMoney < 0
        ? ZadTokens.danger
        : ratio >= 0.8
        ? ZadTokens.warning
        : ZadTokens.primary;
    final todayColor = s.isOverDailyLimit
        ? ZadTokens.danger
        : (s.safeDailyLimit > 0 && s.todaySpending >= 0.8 * s.safeDailyLimit)
        ? ZadTokens.warning
        : ZadTokens.text;

    // One status banner only — worst condition wins.
    final String status;
    final ZadBannerKind kind;
    if (s.remainingMoney < 0) {
      status = 'تجاوزت الميزانية';
      kind = ZadBannerKind.danger;
    } else if (s.isOverDailyLimit) {
      status = 'تجاوزت الحد اليومي — حاول تقليل مصاريف اليوم';
      kind = ZadBannerKind.danger;
    } else if (s.daysRemaining == 0) {
      status = 'انتهت مدة هذه الخطة';
      kind = ZadBannerKind.warning;
    } else if (ratio >= 0.8) {
      status = 'انتبه، اقتربت من الحد';
      kind = ZadBannerKind.warning;
    } else {
      status = 'الوضع جيد';
      kind = ZadBannerKind.success;
    }

    return ZadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
            // Bar fills 0 → ratio once on load; retargets smoothly on data
            // change. Value is display-only, calculations untouched.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
                color: barColor,
                backgroundColor: ZadTokens.goldSoft.withValues(alpha: 0.5),
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
          ZadInfoBanner(status, kind: kind),
        ],
      ),
    );
  }
}
