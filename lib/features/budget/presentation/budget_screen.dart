import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_animated_entry.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/zad_section_header.dart';
import '../../../services/auth_service.dart';
import '../data/budget_cache_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';
import 'widgets/budget_quick_action_card.dart';
import 'widgets/budget_summary_card.dart';
import 'widgets/recurring_purchases_card.dart';
import 'widgets/spending_progress_card.dart';

class BudgetScreen extends StatefulWidget {
  final AuthService authService;
  final BudgetService? budgetService;

  const BudgetScreen({
    super.key,
    required this.authService,
    this.budgetService,
  });

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  late final BudgetService _budget;
  late final BudgetCacheService _cacheService;
  BudgetOverview? _overview;
  List<TodayRecurringPurchase> _todayRecurring = [];
  List<RecurringPurchase> _recurringItems = [];
  RecurringPurchaseOverview? _recurringStats;
  bool _isLoading = true;
  String? _error;
  bool _isOfflineCached = false;
  DateTime? _cachedAt;

  @override
  void initState() {
    super.initState();
    _budget = widget.budgetService ?? BudgetService(widget.authService);
    _cacheService = BudgetCacheService();
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
      final recurringItems = await _budget.getRecurringPurchases();
      final recurringStats = await _budget.getRecurringPurchaseOverview();
      final profileId = widget.authService.profile?.id;
      if (mounted && profileId != null) {
        await _cacheService.save(
          profileId,
          BudgetCachePayload(
            cachedAt: DateTime.now(),
            overview: ov,
            todayRecurring: today,
            recurringItems: recurringItems,
            recurringStats: recurringStats,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _overview = ov;
          _todayRecurring = today;
          _recurringItems = recurringItems;
          _recurringStats = recurringStats;
          _isLoading = false;
          _isOfflineCached = false;
          _cachedAt = null;
        });
      }
    } catch (e) {
      final profileId = widget.authService.profile?.id;
      if (mounted && profileId != null) {
        final cached = await _cacheService.load(profileId);
        if (mounted && cached != null) {
          setState(() {
            _overview = cached.overview;
            _todayRecurring = cached.todayRecurring;
            _recurringItems = cached.recurringItems;
            _recurringStats = cached.recurringStats;
            _isLoading = false;
            _isOfflineCached = true;
            _cachedAt = cached.cachedAt;
          });
          return;
        }
      }
      if (mounted) {
        setState(() {
          _error = _arabicError(e);
          _isLoading = false;
        });
      }
    }
  }

  void _onOfflineAction() {
    _showError('هذه العملية تحتاج إلى اتصال بالإنترنت');
  }

  Future<void> _markRecurring(
    TodayRecurringPurchase item,
    String status,
  ) async {
    if (_isOfflineCached) { _onOfflineAction(); return; }
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
    if (_isOfflineCached) { _onOfflineAction(); return; }
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
    if (_isOfflineCached) { _onOfflineAction(); return; }
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
                if (_isOfflineCached)
                  ZadInfoBanner(
                    _cachedAt != null
                        ? 'أنت تشاهد آخر نسخة محفوظة\nآخر تحديث: ${_fmtDateTime(_cachedAt!)}'
                        : 'أنت تشاهد آخر نسخة محفوظة',
                    kind: ZadBannerKind.warning,
                  ),
                if (_overview != null) ..._body(_overview!),
              ],
            ),
    );
  }

  List<Widget> _body(BudgetOverview ov) {
    return [
      ZadAnimatedEntry(
        child: BudgetSummaryCard(
          plan: ov.budgetPlan,
          summary: ov.summary,
          onSetup: _goSetup,
        ),
      ),
      if (ov.budgetPlan != null && ov.summary != null) ...[
        const SizedBox(height: ZadTokens.s3),
        ZadAnimatedEntry(
          delay: const Duration(milliseconds: 60),
          child: SpendingProgressCard(
            plan: ov.budgetPlan!,
            summary: ov.summary!,
          ),
        ),
      ],
      const ZadSectionHeader('إجراءات سريعة'),
      // Row of 4 circular actions (Stitch); first one gold-filled.
      ZadAnimatedEntry(
        delay: const Duration(milliseconds: 120),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BudgetQuickActionCard(
                icon: Icons.add_circle_outline,
                label: 'إضافة مصروف',
                filled: true,
                enabled: !_isOfflineCached,
                onTap: _isOfflineCached
                    ? _onOfflineAction
                    : () => context
                        .push('/budget/expense/new')
                        .then((_) => _load()),
              ),
            ),
            Expanded(
              child: BudgetQuickActionCard(
                icon: Icons.tune_outlined,
                label: 'إعداد الميزانية',
                enabled: !_isOfflineCached,
                onTap: _isOfflineCached ? _onOfflineAction : _goSetup,
              ),
            ),
            Expanded(
              child: BudgetQuickActionCard(
                icon: Icons.autorenew_outlined,
                label: 'الاشتراكات',
                enabled: !_isOfflineCached,
                onTap: _isOfflineCached
                    ? _onOfflineAction
                    : () => context
                        .push('/budget/subscription/new')
                        .then((_) => _load()),
              ),
            ),
            Expanded(
              child: BudgetQuickActionCard(
                icon: Icons.shopping_basket_outlined,
                label: 'المشتريات',
                enabled: !_isOfflineCached,
                onTap: _isOfflineCached
                    ? _onOfflineAction
                    : () =>
                        context.push('/budget/recurring').then((_) => _load()),
              ),
            ),
          ],
        ),
      ),
      ZadSectionHeader(
        'مشتريات اليوم',
        trailing: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: ZadTokens.goldDark,
            padding: const EdgeInsets.symmetric(horizontal: ZadTokens.s2),
            minimumSize: const Size(0, 32),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: () =>
              context.push('/budget/recurring').then((_) => _load()),
          child: const Text('عرض الكل'),
        ),
      ),
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
                  children: [
                    // Status-tinted icon tile (Stitch: green = purchased,
                    // gold = pending, muted = skipped).
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _statusColor(
                          item.status,
                        ).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.shopping_basket_outlined,
                        size: 22,
                        color: _statusColor(item.status),
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
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_statusText(item.status)}'
                            '${item.reminderTime == null ? '' : '  •  تذكير: ${item.reminderTime}'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _statusColor(item.status),
                            ),
                          ),
                        ],
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
                // Gold-tinted tile (Stitch: amber = planned commitment).
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ZadTokens.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.autorenew_outlined,
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
                  // Amber: planned commitment, not an actual expense.
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ZadTokens.warning,
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
      ZadSectionHeader(
        'المشتريات اليومية',
        trailing: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: ZadTokens.goldDark,
            padding: const EdgeInsets.symmetric(horizontal: ZadTokens.s2),
            minimumSize: const Size(0, 32),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: () =>
              context.push('/budget/recurring').then((_) => _load()),
          child: const Text('عرض الكل'),
        ),
      ),
      RecurringPurchasesCard(
        stats: ov.budgetPlan != null ? _recurringStats : null,
        items: _recurringItems,
        todayItems: _todayRecurring,
        onManage: () =>
            context.push('/budget/recurring').then((_) => _load()),
      ),
      if (ov.recentExpenses.isNotEmpty) ...[
        // Stitch title. "التقارير" button rejected: no reports feature.
        const ZadSectionHeader('آخر المصروفات'),
        for (final exp in ov.recentExpenses)
          ZadCard(
            margin: const EdgeInsets.only(bottom: ZadTokens.s2),
            padding: const EdgeInsets.symmetric(
              horizontal: ZadTokens.s4,
              vertical: ZadTokens.s3,
            ),
            child: Row(
              children: [
                // Neutral circular icon tile (Stitch expense rows).
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZadTokens.surfaceContainer,
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    size: 20,
                    color: ZadTokens.textMuted,
                  ),
                ),
                const SizedBox(width: ZadTokens.s3),
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
                  '- ${exp.amount.toStringAsFixed(2)}',
                  // Red: money already spent (Stitch "- 150.00" style).
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ZadTokens.danger,
                  ),
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

  static String _fmtDateTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _statusText(String status) {
    if (status == 'purchased') {
      return 'تم الشراء';
    }
    if (status == 'skipped') {
      return 'لم يتم الشراء';
    }
    return 'لم يحدد بعد';
  }

  // purchased = green, skipped = neutral, pending = amber.
  static Color _statusColor(String status) {
    if (status == 'purchased') return ZadTokens.primary;
    if (status == 'skipped') return ZadTokens.textMuted;
    return ZadTokens.warning;
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
