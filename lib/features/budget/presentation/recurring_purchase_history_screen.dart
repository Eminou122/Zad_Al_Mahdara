import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../services/auth_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';
import 'widgets/recurring_removal_dialog.dart';

class RecurringPurchaseHistoryScreen extends StatefulWidget {
  final AuthService authService;
  final BudgetService? budgetService;

  const RecurringPurchaseHistoryScreen({
    super.key,
    required this.authService,
    this.budgetService,
  });

  @override
  State<RecurringPurchaseHistoryScreen> createState() =>
      _RecurringPurchaseHistoryScreenState();
}

class _RecurringPurchaseHistoryScreenState
    extends State<RecurringPurchaseHistoryScreen> {
  late final BudgetService _budget;
  List<RecurringPurchaseHistoryItem> _items = [];
  final Set<String> _removing = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _budget = widget.budgetService ?? BudgetService(widget.authService);
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _budget.getRecurringPurchaseHistory(limit: 50);
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

  Future<void> _remove(RecurringPurchaseHistoryItem item) async {
    if (_removing.contains(item.occurrenceId)) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => RecurringRemovalDialog(
        title: 'إلغاء عملية الشراء',
        body:
            'سيتم إلغاء عملية الشراء المحددة وعكس أثرها من المصروفات، مع الاحتفاظ بسجلها المالي.',
        details: [
          item.name,
          _date(item.occurrenceDate),
          '${item.price.toStringAsFixed(2)} MRU',
        ],
        actionLabel: 'إلغاء عملية الشراء',
        onSubmit: (reason) async {
          if (_removing.contains(item.occurrenceId)) return;
          setState(() => _removing.add(item.occurrenceId));
          try {
            final result = await _budget.removeRecurringPurchaseOccurrence(
              recurringPurchaseId: item.recurringPurchaseId,
              occurrenceDate: item.occurrenceDate,
              reason: reason,
            );
            if (!mounted) return;
            setState(() => _items = result.history);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'تم إلغاء عملية الشراء مع الاحتفاظ بسجلها المالي',
                ),
              ),
            );
          } finally {
            if (mounted) setState(() => _removing.remove(item.occurrenceId));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ZadScaffold(
    title: 'سجل المشتريات المتكررة',
    onRefresh: _load,
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error != null)
                ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
              if (_items.isEmpty)
                const ZadCard(
                  child: Text(
                    'لا توجد عمليات مسجلة',
                    style: TextStyle(color: ZadTokens.textMuted),
                  ),
                ),
              for (final item in _items)
                ZadCard(
                  margin: const EdgeInsets.only(bottom: ZadTokens.s2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: ZadTokens.s1),
                      Text(
                        '${_date(item.occurrenceDate)}  •  ${item.price.toStringAsFixed(2)} MRU',
                      ),
                      Text(
                        _status(item),
                        style: const TextStyle(color: ZadTokens.textMuted),
                      ),
                      if (item.status == 'purchased' && !item.isVoided)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _removing.contains(item.occurrenceId)
                                ? null
                                : () => _remove(item),
                            icon: const Icon(
                              Icons.cancel_outlined,
                              color: ZadTokens.danger,
                            ),
                            label: const Text('إلغاء عملية الشراء'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
  );

  static String _status(RecurringPurchaseHistoryItem item) => item.isVoided
      ? 'ملغاة'
      : item.status == 'skipped'
      ? 'تم التخطي'
      : 'تم الشراء';
  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _arabicError(Object e) => e is PostgrestException
      ? 'خطأ: ${e.message}'
      : 'حدث خطأ — تحقق من اتصالك بالإنترنت';
}
