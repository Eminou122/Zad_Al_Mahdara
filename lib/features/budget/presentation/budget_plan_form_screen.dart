import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';

class BudgetPlanFormScreen extends StatefulWidget {
  final AuthService authService;
  final BudgetPlan? existingPlan;

  const BudgetPlanFormScreen({
    super.key,
    required this.authService,
    this.existingPlan,
  });

  @override
  State<BudgetPlanFormScreen> createState() => _BudgetPlanFormScreenState();
}

class _BudgetPlanFormScreenState extends State<BudgetPlanFormScreen> {
  late final BudgetService _budget;
  final _moneyCtrl = TextEditingController();
  final _noteCtrl  = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _budget = BudgetService(widget.authService);
    final p = widget.existingPlan;
    if (p != null) {
      _moneyCtrl.text = p.totalMoney.toStringAsFixed(2);
      _noteCtrl.text  = p.note ?? '';
      _startDate = p.startDate;
      _endDate   = p.endDate;
    }
  }

  @override
  void dispose() {
    _moneyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now    = DateTime.now();
    final init   = isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 1),
      lastDate:  DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) { _startDate = picked; } else { _endDate = picked; }
    });
  }

  Future<void> _submit() async {
    final money = double.tryParse(_moneyCtrl.text.trim());
    if (money == null || money < 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً (صفر أو أكثر)');
      return;
    }
    if (_startDate == null) {
      setState(() => _error = 'اختر تاريخ البداية');
      return;
    }
    if (_endDate == null) {
      setState(() => _error = 'اختر تاريخ النهاية');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _error = 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية');
      return;
    }
    final note = _noteCtrl.text.trim();
    if (note.length > 300) {
      setState(() => _error = 'الملاحظة طويلة جداً');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await _budget.upsertBudgetPlan(
        totalMoney: money,
        startDate:  _startDate!,
        endDate:    _endDate!,
        note:       note.isEmpty ? null : note,
      );
      if (mounted) context.pop();
    } on PostgrestException catch (e) {
      if (mounted) setState(() { _error = _arabicError(e.message); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'حدث خطأ — تحقق من اتصالك'; _loading = false; });
    }
  }

  static String _arabicError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('end_date')) return 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية';
    if (m.contains('total_money')) return 'المبلغ يجب أن يكون صفر أو أكثر';
    if (m.contains('note')) return 'الملاحظة طويلة جداً';
    if (m.contains('invalid session')) return 'انتهت جلستك — يرجى إعادة تسجيل الدخول';
    return 'حدث خطأ: $msg';
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingPlan != null;
    return ZadScaffold(
      title: 'إعداد الميزانية',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TipCard('اكتب المبلغ الكامل ومدة بقائك في المحظرة.'),
          if (_error != null)
            ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
          TextField(
            controller: _moneyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المبلغ الإجمالي (MRU)'),
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'تاريخ البداية',
            date: _startDate,
            onTap: () => _pickDate(true),
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'تاريخ النهاية',
            date: _endDate,
            onTap: () => _pickDate(false),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'ملاحظة (اختياري)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(isEdit ? 'تحديث الميزانية' : 'حفظ الميزانية'),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = date == null
        ? 'اختر التاريخ'
        : '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(text),
      ),
    );
  }
}
