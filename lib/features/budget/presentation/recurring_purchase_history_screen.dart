import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/zad_tokens.dart';
import '../../../core/widgets/zad_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../core/widgets/zad_permanent_delete_confirm.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/zad_section_header.dart';
import '../../../services/auth_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';

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
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;
  bool _deleting = false;
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

  Future<void> _delete(List<String> ids) async {
    if (ids.isEmpty || _deleting) return;
    if (!await zadPermanentDeleteConfirm(context, count: ids.length)) return;
    setState(() => _deleting = true);
    try {
      await _budget.deleteRecurringPurchaseOccurrences(ids);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((item) => ids.contains(item.occurrenceId));
        _selectedIds.removeAll(ids);
        _selectionMode = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_arabicError(e))));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _toggle(String id) => setState(
    () => _selectedIds.contains(id)
        ? _selectedIds.remove(id)
        : _selectedIds.add(id),
  );

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
              if (_items.isNotEmpty) ...[
                const ZadSectionHeader('سجل المشتريات'),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: ZadTokens.s2,
                    runSpacing: ZadTokens.s1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!_selectionMode)
                        TextButton(
                          onPressed: () =>
                              setState(() => _selectionMode = true),
                          child: const Text('تحديد'),
                        )
                      else ...[
                        TextButton(
                          onPressed: () => setState(
                            () => _selectedIds.addAll(
                              _items.map((item) => item.occurrenceId),
                            ),
                          ),
                          child: const Text('تحديد الكل'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedIds.clear();
                            _selectionMode = false;
                          }),
                          child: const Text('إلغاء التحديد'),
                        ),
                        if (_selectedIds.isNotEmpty) ...[
                          Text('تم تحديد ${_selectedIds.length}'),
                          TextButton(
                            onPressed: _deleting
                                ? null
                                : () => _delete(_selectedIds.toList()),
                            child: const Text('حذف المحدد'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
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
                      if (_selectionMode)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Checkbox(
                            value: _selectedIds.contains(item.occurrenceId),
                            onChanged: (_) => _toggle(item.occurrenceId),
                          ),
                        )
                      else
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _deleting
                                ? null
                                : () => _delete([item.occurrenceId]),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: ZadTokens.danger,
                            ),
                            label: const Text('حذف نهائياً'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
  );

  static String _status(RecurringPurchaseHistoryItem item) =>
      item.status == 'skipped' ? 'تم التخطي' : 'تم الشراء';
  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _arabicError(Object e) => e is PostgrestException
      ? 'خطأ: ${e.message}'
      : 'حدث خطأ — تحقق من اتصالك بالإنترنت';
}
