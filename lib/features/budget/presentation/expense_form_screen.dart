import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';

class ExpenseFormScreen extends StatefulWidget {
  final AuthService authService;
  final Expense? existingExpense;
  final BudgetService? budgetService;

  const ExpenseFormScreen({
    super.key,
    required this.authService,
    this.existingExpense,
    this.budgetService,
  });

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final BudgetService _budget;
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime? _date;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _budget = widget.budgetService ?? BudgetService(widget.authService);
    final e = widget.existingExpense;
    if (e != null) {
      _nameCtrl.text = e.itemName;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _noteCtrl.text = e.note ?? '';
      _date = e.expenseDate;
    } else {
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_loading) return;
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    final note = _noteCtrl.text.trim();

    if (name.isEmpty || name.length > 80) {
      setState(() => _error = 'اسم المصروف مطلوب (1–80 حرف)');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً أكبر من صفر');
      return;
    }
    if (_date == null) {
      setState(() => _error = 'اختر تاريخ المصروف');
      return;
    }
    if (note.length > 300) {
      setState(() => _error = 'الملاحظة طويلة جداً');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final BudgetOverview overview;
      final ex = widget.existingExpense;
      if (ex != null) {
        overview = await _budget.updateExpense(
          expenseId: ex.id,
          itemName: name,
          amount: amount,
          note: note.isEmpty ? null : note,
          expenseDate: _date!,
        );
      } else {
        overview = await _budget.addExpense(
          itemName: name,
          amount: amount,
          note: note.isEmpty ? null : note,
          expenseDate: _date!,
        );
      }
      if (mounted) context.pop(overview);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _error = _arabicError(e.message);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'حدث خطأ — تحقق من اتصالك';
          _loading = false;
        });
      }
    }
  }

  static String _arabicError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('expense_date outside')) {
      return 'التاريخ خارج نطاق الميزانية الحالية';
    }
    if (m.contains('item_name')) return 'اسم المصروف غير صالح';
    if (m.contains('amount')) return 'المبلغ يجب أن يكون أكبر من صفر';
    if (m.contains('invalid session')) {
      return 'انتهت جلستك — يرجى إعادة تسجيل الدخول';
    }
    return 'حدث خطأ: $msg';
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingExpense != null;
    final dateText = _date == null
        ? 'اختر التاريخ'
        : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';

    return ZadScaffold(
      title: isEdit ? 'تعديل المصروف' : 'إضافة مصروف',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TipCard('سجل ما صرفته اليوم ليتم حساب المال المتبقي.'),
          if (_error != null)
            ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
          TextField(
            controller: _nameCtrl,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'اسم المصروف',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المبلغ (MRU)'),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'التاريخ',
                suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
              ),
              child: Text(dateText),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'ملاحظة اختيارية',
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(isEdit ? 'تحديث المصروف' : 'إضافة المصروف'),
          ),
        ],
      ),
    );
  }
}
