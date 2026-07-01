import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../services/auth_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';

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

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'ميزانيتي',
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TipCard(
                  'هنا تعرف كم بقي من مالك وكم يمكنك أن تصرف كل يوم بأمان.',
                ),
                if (_error != null) _ErrorBox(_error!),
                if (_overview != null) ..._body(_overview!),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context
                      .push('/budget/setup', extra: _overview?.budgetPlan)
                      .then((_) => _load()),
                  child: const Text('إعداد الميزانية'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () =>
                      context.push('/budget/expense/new').then((_) => _load()),
                  child: const Text('إضافة مصروف'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => context
                      .push('/budget/subscription/new')
                      .then((_) => _load()),
                  child: const Text('إضافة اشتراك'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () =>
                      context.push('/budget/recurring').then((_) => _load()),
                  child: const Text('المشتريات المتكررة'),
                ),
              ],
            ),
    );
  }

  List<Widget> _body(BudgetOverview ov) {
    final widgets = <Widget>[];

    if (ov.budgetPlan == null) {
      widgets.add(_WarningBox('أنشئ خطة ميزانية أولاً'));
    } else {
      final plan = ov.budgetPlan!;
      final s = ov.summary!;

      if (s.daysRemaining == 0) {
        widgets.add(_WarningBox('انتهت مدة هذه الخطة.'));
      }
      if (s.remainingMoney < 0) {
        widgets.add(
          _WarningBox(
            'انتهى المال المخطط أو أصبح أقل من الصفر.',
            color: Colors.orange.shade700,
          ),
        );
      }
      if (s.isOverDailyLimit) {
        widgets.add(
          _WarningBox('صرفت اليوم أكثر من الحد الآمن. حاول تقليل المصاريف.'),
        );
      }

      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row(
                  'إجمالي الميزانية',
                  '${plan.totalMoney.toStringAsFixed(2)} MRU',
                ),
                _row(
                  'المتبقي',
                  '${s.remainingMoney.toStringAsFixed(2)} MRU',
                  color: s.remainingMoney < 0
                      ? Colors.red
                      : const Color(0xFF2E7D32),
                ),
                _row(
                  'الحد اليومي الآمن',
                  '${s.safeDailyLimit < 0 ? 0 : s.safeDailyLimit.toStringAsFixed(2)} MRU',
                ),
                _row(
                  'مصروف اليوم',
                  '${s.todaySpending.toStringAsFixed(2)} MRU',
                ),
                _row('الأيام المتبقية', '${s.daysRemaining} / ${s.daysTotal}'),
                if (plan.note != null && plan.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      plan.note!,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      widgets.add(const SizedBox(height: 16));
      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row(
                  'المتوقع من المشتريات المتكررة',
                  '${s.plannedRecurringTotal.toStringAsFixed(2)} MRU',
                ),
                _row(
                  'تم شراؤه فعلاً',
                  '${s.actualRecurringTotal.toStringAsFixed(2)} MRU',
                ),
                _row(
                  'لم يتم شراؤه',
                  '${s.skippedRecurringTotal.toStringAsFixed(2)} MRU (${s.skippedRecurringCount})',
                ),
              ],
            ),
          ),
        ),
      );
    }

    widgets.add(const SizedBox(height: 16));
    widgets.add(_sectionTitle('مشتريات اليوم'));
    if (_todayRecurring.isEmpty) {
      widgets.add(
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('لا توجد مشتريات متكررة اليوم'),
          ),
        ),
      );
    } else {
      for (final item in _todayRecurring) {
        widgets.add(
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.price.toStringAsFixed(2)} MRU'
                    '${item.reminderTime == null ? '' : '  •  تذكير: ${item.reminderTime}'}',
                  ),
                  const SizedBox(height: 6),
                  Text('الحالة: ${_statusText(item.status)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: item.status == 'purchased'
                            ? null
                            : () => _markRecurring(item, 'purchased'),
                        child: const Text('تم الشراء'),
                      ),
                      OutlinedButton(
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
          ),
        );
      }
    }

    if (ov.activeSubscriptions.isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(_sectionTitle('الاشتراكات الفعالة'));
      for (final sub in ov.activeSubscriptions) {
        widgets.add(
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(
                sub.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${sub.amount.toStringAsFixed(2)} MRU  •  ${_fmtDate(sub.startDate)} ← ${_fmtDate(sub.endDate)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      color: Colors.red,
                    ),
                    tooltip: 'إلغاء',
                    onPressed: () => _deactivateSub(sub.id),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (ov.recentExpenses.isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(_sectionTitle('المصاريف الأخيرة'));
      for (final exp in ov.recentExpenses) {
        widgets.add(
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(
                exp.itemName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${exp.amount.toStringAsFixed(2)} MRU  •  ${_fmtDate(exp.expenseDate)}'
                '${exp.category != null ? "  •  ${exp.category}" : ""}'
                '${exp.source == "recurring_purchase" ? "  •  متكرر" : ""}',
              ),
              trailing: exp.source == 'manual'
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                            color: Colors.red,
                          ),
                          tooltip: 'حذف',
                          onPressed: () => _deleteExpense(exp.id),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        );
      }
    }

    return widgets;
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
    ),
  );

  Widget _row(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
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

class _WarningBox extends StatelessWidget {
  final String message;
  final Color? color;
  const _WarningBox(this.message, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.red.shade700;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(message, style: TextStyle(color: c)),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(message, style: TextStyle(color: Colors.red.shade800)),
    );
  }
}
