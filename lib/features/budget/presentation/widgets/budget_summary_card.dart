import 'package:flutter/material.dart';
import '../../../../core/theme/zad_tokens.dart';
import '../../../../core/widgets/zad_card.dart';
import '../../../../core/widgets/zad_dotted_background.dart';
import '../../domain/budget_models.dart';

/// Stitch-style budget hero: green banner with remaining money, two tinted
/// metric mini-cards, and a safe-daily-limit banner. Falls back to an empty
/// state with an inline setup action when no budget plan exists.
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
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ZadTokens.gold.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 32,
                color: ZadTokens.gold,
              ),
            ),
            const SizedBox(height: ZadTokens.s3),
            Text(
              'لا توجد خطة ميزانية بعد',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
    final lowRemaining =
        p.totalMoney > 0 && s.remainingMoney / p.totalMoney <= 0.15;
    final statusColor = s.remainingMoney < 0
        ? ZadTokens.danger
        : lowRemaining
        ? ZadTokens.warning
        : ZadTokens.gold;
    final statusLabel = s.remainingMoney < 0
        ? 'تجاوزت الميزانية'
        : lowRemaining
        ? 'المتبقي قليل — انتبه'
        : 'الوضع جيد';
    final daysColor = s.daysRemaining == 0
        ? ZadTokens.danger
        : s.daysRemaining <= 3
        ? ZadTokens.warning
        : ZadTokens.primary;
    final limitColor = (s.remainingMoney <= 0 || safeLimit <= 0)
        ? ZadTokens.danger
        : ZadTokens.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Green hero banner (Stitch budget_dashboard).
        ClipRRect(
          borderRadius: BorderRadius.circular(ZadTokens.radiusLg),
          child: Container(
            decoration: const BoxDecoration(
              gradient: ZadTokens.heroGradient,
              boxShadow: ZadTokens.cardShadow,
            ),
            child: ZadDottedBackground(
              color: Colors.white12,
              child: Stack(
                children: [
                  const PositionedDirectional(
                    start: 18,
                    top: 16,
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 88,
                      color: Colors.white12,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(ZadTokens.s5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الرصيد المتبقي',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: ZadTokens.s1),
                        Text(
                          '${s.remainingMoney.toStringAsFixed(2)} MRU',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: ZadTokens.s2),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: ZadTokens.s2),
                            Text(
                              statusLabel,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: ZadTokens.s3),
        // Two tinted metric mini-cards (Stitch).
        Row(
          children: [
            Expanded(
              child: _MetricBox(
                label: 'إجمالي الميزانية',
                value: '${p.totalMoney.toStringAsFixed(0)} MRU',
                valueColor: ZadTokens.text,
              ),
            ),
            const SizedBox(width: ZadTokens.s3),
            Expanded(
              child: _MetricBox(
                label: 'الأيام المتبقية',
                value: '${s.daysRemaining} / ${s.daysTotal} يوم',
                valueColor: daysColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: ZadTokens.s3),
        // Safe daily limit banner with shield (Stitch).
        Container(
          padding: const EdgeInsets.all(ZadTokens.s3),
          decoration: BoxDecoration(
            color: ZadTokens.surfaceContainer,
            borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 20, color: limitColor),
              const SizedBox(width: ZadTokens.s2 + 2),
              const Expanded(
                child: Text(
                  'الحد اليومي الآمن',
                  style: TextStyle(fontSize: 13, color: ZadTokens.text),
                ),
              ),
              Text(
                '${safeLimit.toStringAsFixed(0)} MRU',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: limitColor,
                ),
              ),
            ],
          ),
        ),
        if (p.note != null && p.note!.isNotEmpty) ...[
          const SizedBox(height: ZadTokens.s2),
          Text(
            p.note!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
          ),
        ],
      ],
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _MetricBox({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZadTokens.s3),
      decoration: BoxDecoration(
        color: ZadTokens.surfaceContainer,
        borderRadius: BorderRadius.circular(ZadTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: ZadTokens.textMuted),
          ),
          const SizedBox(height: ZadTokens.s1),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
