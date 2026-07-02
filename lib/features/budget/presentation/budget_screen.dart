import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/zad_section_header.dart';
import '../../../services/auth_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';
import 'widgets/budget_quick_action_card.dart';
import 'widgets/budget_summary_card.dart';
import 'widgets/spending_progress_card.dart';

class BudgetScreen extends StatefulWidget {
  final AuthService authService;
  const BudgetScreen({super.key, required this.authService});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  late final BudgetService _budget;
  BudgetOverview? _overview;
  List<TodayRecurringPurchase> _todayRecurring = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _budget = BudgetService(widget.authService);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final ov = await _budget.getOverview();
      final today = await _budget.getTodayRecurringPurchases();
      if (mounted) {
        setState(() {
          _overview = ov;
          _todayRecurring = today;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _arabicError(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markRecurring(
    TodayRecurringPurchase item,
    String status,
  ) async {
    try {
      await _budget.markRecurringPurchaseOccurrence(
        recurringPurchaseId: item.recurringPurchaseId,
        occurrenceDate: item.occurrenceDate,
        status: status,
      );
      _load();
    } catch (e) {
      if (mounted) _showError(_arabicError(e));
    }
  }

  Future<void> _deleteExpense(String id) async {
    final ok = await _confirm('حذف المصروف', 'هل تريد حذف هذا المصروف؟');
    if (!ok) return;
    try {
      await _budget.deleteExpense(id);
      _load();
    } catch (e) {
      if (mounted) _showError(_arabicError(e));
    }
  }

  Future<void> _deactivateSub(String id) async {
    final ok = await _confirm(
      'إلغاء الاشتراك',
      'هل تريد إلغاء تفعيل هذا الاشتراك؟',
    );
    if (!ok) return;
    try {
      await _budget.deactivateSubscription(id);
      _load();
    } catch (e) {
      if (mounted) _showError(_arabicError(e));
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _goSetup() => context
      .push('/budget/setup', extra: _overview?.budgetPlan)
      .then((_) => _load());

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'ميزانيتي',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                if (_overview != null) ..._body(_overview!),
              ],
            ),
    );
  }

  List<Widget> _body(BudgetOverview ov) {
    return [
      BudgetSummaryCard(
        plan: ov.budgetPlan,
        summary: ov.summary,
        onSetup: _goSetup,
      ),
      if (ov.budgetPlan != null && ov.summary != null) ...[
        const SizedBox(height: ZadTokens.s3),
        SpendingProgressCard(plan: ov.budgetPlan!, summary: ov.summary!),
      ],
      const ZadSectionHeader('إجراءات سريعة'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: ZadTokens.s3,
        crossAxisSpacing: ZadTokens.s3,
        // 1.75 leaves room for two-line Arabic labels at 320px width.
        childAspectRatio: 1.75,
        children: [
          BudgetQuickActionCard(
            icon: Icons.add_circle_outline,
            label: 'إضافة مصروف',
            onTap: () =>
                context.push('/budget/expense/new').then((_) => _load()),
          ),
          BudgetQuickActionCard(
            icon: Icons.tune_outlined,
            label: 'إعداد الميزانية',
            onTap: _goSetup,
          ),
          BudgetQuickActionCard(
            icon: Icons.autorenew_outlined,
            label: 'الاشتراكات',
            onTap: () =>
                context.push('/budget/subscription/new').then((_) => _load()),
          ),
          BudgetQuickActionCard(
            icon: Icons.shopping_basket_outlined,
            label: 'المشتريات المتكررة',
            onTap: () =>
                context.push('/budget/recurring').then((_) => _load()),
          ),
        ],
      ),
      const ZadSectionHeader('مشتريات اليوم'),
      if (_todayRecurring.isEmpty)
        const ZadCard(
          child: Text(
            'لا توجد مشتريات متكررة اليوم',
            style: TextStyle(color: ZadTokens.textMuted),
          ),
        )
      else
        for (final item in _todayRecurring)
          ZadCard(
            margin: const EdgeInsets.only(bottom: ZadTokens.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '${item.price.toStringAsFixed(2)} MRU',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: ZadTokens.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZadTokens.s1),
                Text(
                  '${_statusText(item.status)}'
                  '${item.reminderTime == null ? '' : '  •  تذكير: ${item.reminderTime}'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZadTokens.textMuted,
                  ),
                ),
                const SizedBox(height: ZadTokens.s2),
                Row(
                  children: [
                    ElevatedButton(
                      style: _chipStyle,
                      onPressed: item.status == 'purchased'
                          ? null
                          : () => _markRecurring(item, 'purchased'),
                      child: const Text('تم الشراء'),
                    ),
                    const SizedBox(width: ZadTokens.s2),
                    OutlinedButton(
                      style: _chipStyle,
                      onPressed: item.status == 'skipped'
                          ? null
                          : () => _markRecurring(item, 'skipped'),
                      child: const Text('لم أشترِ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      if (ov.activeSubscriptions.isNotEmpty) ...[
        const ZadSectionHeader('الاشتراكات الفعالة'),
        for (final sub in ov.activeSubscriptions)
          ZadCard(
            margin: const EdgeInsets.only(bottom: ZadTokens.s2),
            padding: const EdgeInsets.symmetric(
              horizontal: ZadTokens.s4,
              vertical: ZadTokens.s3,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.autorenew_outlined,
                  color: ZadTokens.gold,
                  size: 22,
                ),
                const SizedBox(width: ZadTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_fmtDate(sub.startDate)} ← ${_fmtDate(sub.endDate)}'
                        '  •  إشعار قبل ${sub.notifyDaysBefore} أيام',
                        style: const TextStyle(
                          fontSize: 12,
                          color: ZadTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${sub.amount.toStringAsFixed(2)} MRU',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ZadTokens.primary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'تعديل',
                  onPressed: () => context
                      .push('/budget/subscription/new', extra: sub)
                      .then((_) => _load()),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.cancel_outlined,
                    size: 20,
                    color: ZadTokens.danger,
                  ),
                  tooltip: 'إلغاء',
                  onPressed: () => _deactivateSub(sub.id),
                ),
              ],
            ),
          ),
      ],
      if (ov.recentExpenses.isNotEmpty) ...[
        const ZadSectionHeader('المصاريف الأخيرة'),
        for (final exp in ov.recentExpenses)
          ZadCard(
            margin: const EdgeInsets.only(bottom: ZadTokens.s2),
            padding: const EdgeInsets.symmetric(
              horizontal: ZadTokens.s4,
              vertical: ZadTokens.s3,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exp.itemName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _fmtDate(exp.expenseDate) +
                            (exp.category != null
                                ? '  •  ${exp.category}'
                                : '') +
                            (exp.source == 'recurring_purchase'
                                ? '  •  متكرر'
                                : ''),
                        style: const TextStyle(
                          fontSize: 12,
                          color: ZadTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${exp.amount.toStringAsFixed(2)} MRU',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (exp.source == 'manual') ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'تعديل',
                    onPressed: () => context
                        .push('/budget/expense/new', extra: exp)
                        .then((_) => _load()),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: ZadTokens.danger,
                    ),
                    tooltip: 'حذف',
                    onPressed: () => _deleteExpense(exp.id),
                  ),
                ],
              ],
            ),
          ),
      ],
    ];
  }

  static final _chipStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: ZadTokens.s4),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    ),
  );

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _statusText(String status) {
    if (status == 'purchased') {
      return 'تم الشراء';
    }
    if (status == 'skipped') {
      return 'لم يتم الشراء';
    }
    return 'لم يحدد بعد';
  }

  static String _arabicError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('invalid session')) {
      return 'انتهت جلستك — يرجى إعادة تسجيل الدخول';
    }
    if (msg.contains('expense_date outside')) {
      return 'التاريخ خارج نطاق الميزانية';
    }
    if (msg.contains('not found') || msg.contains('not deletable')) {
      return 'العنصر غير موجود';
    }
    if (e is PostgrestException) return 'خطأ: ${e.message}';
    return 'حدث خطأ — تحقق من اتصالك بالإنترنت';
  }
}
