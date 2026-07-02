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
import '../data/budget_service.dart';
import '../domain/budget_models.dart';

class RecurringPurchasesScreen extends StatefulWidget {
  final AuthService authService;

  const RecurringPurchasesScreen({super.key, required this.authService});

  @override
  State<RecurringPurchasesScreen> createState() =>
      _RecurringPurchasesScreenState();
}

class _RecurringPurchasesScreenState extends State<RecurringPurchasesScreen> {
  late final BudgetService _budget;
  List<RecurringPurchase> _items = [];
  RecurringPurchaseOverview? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _budget = BudgetService(widget.authService);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _budget.getRecurringPurchases();
      final stats = await _budget.getRecurringPurchaseOverview();
      if (mounted) {
        setState(() {
          _items = items;
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _arabicError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _deactivate(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إلغاء التفعيل'),
        content: const Text('هل تريد إلغاء تفعيل هذا الشراء المتكرر؟'),
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
    if (ok != true) return;
    try {
      await _budget.deactivateRecurringPurchase(id);
      _load();
    } catch (e) {
      if (mounted) setState(() => _error = _arabicError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ZadScaffold(
      title: 'المشتريات المتكررة',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ZadAnimatedEntry(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ZadInfoBanner(
                    'أضف الأشياء التي تشتريها كثيراً، مثل الحليب أو الخبز، ثم علّم ما اشتريته اليوم. التذكير للعرض داخل التطبيق فقط.',
                  ),
                  if (_error != null)
                    ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                  if (_stats != null) _statsCard(_stats!),
                  const ZadSectionHeader('قائمة المشتريات'),
                  if (_items.isEmpty)
                    const ZadCard(
                      child: Text(
                        'لا توجد مشتريات متكررة حالياً',
                        style: TextStyle(color: ZadTokens.textMuted),
                      ),
                    ),
                  for (final item in _items)
                    ZadCard(
                      margin: const EdgeInsets.only(bottom: ZadTokens.s2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZadTokens.s4,
                        vertical: ZadTokens.s3,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shopping_basket_outlined,
                            color: ZadTokens.gold,
                            size: 22,
                          ),
                          const SizedBox(width: ZadTokens.s3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_freq(item)}  •  ${_fmtDate(item.startDate)} ← ${_fmtDate(item.endDate)}'
                                  '${item.reminderTime == null ? '' : '\nتذكير: ${item.reminderTime}'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ZadTokens.textMuted,
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
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'تعديل',
                            onPressed: () => context
                                .push('/budget/recurring/new', extra: item)
                                .then((_) => _load()),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.cancel_outlined,
                              size: 20,
                              color: ZadTokens.danger,
                            ),
                            tooltip: 'إلغاء التفعيل',
                            onPressed: () => _deactivate(item.id),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: ZadTokens.s4),
                  ElevatedButton(
                    onPressed: () => context
                        .push('/budget/recurring/new')
                        .then((_) => _load()),
                    child: const Text('إضافة شراء متكرر'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statsCard(RecurringPurchaseOverview s) {
    return ZadCard(
      margin: const EdgeInsets.only(bottom: ZadTokens.s2),
      child: Column(
        children: [
          _statRow(
            'المتوقع من المشتريات المتكررة',
            '${s.plannedTotal.toStringAsFixed(2)} MRU',
          ),
          _statRow(
            'تم شراؤه فعلاً',
            '${s.actualPurchasedTotal.toStringAsFixed(2)} MRU',
            color: ZadTokens.primary,
          ),
          _statRow(
            'لم يتم شراؤه',
            '${s.skippedTotal.toStringAsFixed(2)} MRU (${s.skippedCount})',
            color: ZadTokens.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? color}) => Padding(
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
        const SizedBox(width: ZadTokens.s2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color,
          ),
        ),
      ],
    ),
  );

  static String _freq(RecurringPurchase item) {
    if (item.frequency == 'daily') {
      return 'كل يوم';
    }
    if (item.frequency == 'weekly') {
      return 'كل أسبوع';
    }
    return 'كل ${item.intervalDays ?? 2} أيام';
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _arabicError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('invalid session')) {
      return 'انتهت جلستك — يرجى إعادة تسجيل الدخول';
    }
    if (msg.contains('not found')) {
      return 'العنصر غير موجود';
    }
    if (e is PostgrestException) return 'خطأ: ${e.message}';
    return 'حدث خطأ — تحقق من اتصالك بالإنترنت';
  }
}
