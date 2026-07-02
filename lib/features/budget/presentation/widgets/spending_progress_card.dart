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
    final barColor = s.remainingMoney < 0
        ? ZadTokens.danger
        : ratio >= 0.85
            ? ZadTokens.warning
            : ZadTokens.primary;

    String? warning;
    ZadBannerKind kind = ZadBannerKind.warning;
    if (s.remainingMoney < 0) {
      warning = 'انتهى المال المخطط أو أصبح أقل من الصفر.';
      kind = ZadBannerKind.danger;
    } else if (s.daysRemaining == 0) {
      warning = 'انتهت مدة هذه الخطة.';
    } else if (s.isOverDailyLimit) {
      warning = 'صرفت اليوم أكثر من الحد الآمن. حاول تقليل المصاريف.';
    }

    return ZadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المصروف',
                  style: TextStyle(color: ZadTokens.textMuted, fontSize: 13)),
              Text(
                '${s.totalSpent.toStringAsFixed(2)} / ${total.toStringAsFixed(2)} MRU',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: ZadTokens.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(ZadTokens.radiusSm),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              color: barColor,
              backgroundColor: ZadTokens.goldSoft.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: ZadTokens.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('مصروف اليوم',
                  style: TextStyle(color: ZadTokens.textMuted, fontSize: 13)),
              Text(
                '${s.todaySpending.toStringAsFixed(2)} MRU',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: s.isOverDailyLimit ? ZadTokens.danger : ZadTokens.text,
                ),
              ),
            ],
          ),
          if (warning != null) ...[
            const SizedBox(height: ZadTokens.s3),
            ZadInfoBanner(warning, kind: kind),
          ],
        ],
      ),
    );
  }
}
