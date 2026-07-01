import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';
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
      if (mounted) {
        setState(() {
          _items = items;
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TipCard(
                  'أضف الأشياء التي تشتريها كثيراً، مثل الحليب أو الخبز، ثم علّم ما اشتريته اليوم.',
                ),
                const TipCard(
                  'التذكير محفوظ للعرض داخل التطبيق فقط، ولا يرسل إشعاراً حالياً.',
                ),
                if (_error != null) _ErrorBox(_error!),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('لا توجد مشتريات متكررة حالياً'),
                  ),
                for (final item in _items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${item.price.toStringAsFixed(2)} MRU  •  ${_freq(item)}\n'
                        '${_fmtDate(item.startDate)} ← ${_fmtDate(item.endDate)}'
                        '${item.reminderTime == null ? '' : '  •  تذكير: ${item.reminderTime}'}',
                      ),
                      isThreeLine: item.reminderTime != null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                              color: Colors.red,
                            ),
                            tooltip: 'إلغاء التفعيل',
                            onPressed: () => _deactivate(item.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context
                      .push('/budget/recurring/new')
                      .then((_) => _load()),
                  child: const Text('إضافة شراء متكرر'),
                ),
              ],
            ),
    );
  }

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
