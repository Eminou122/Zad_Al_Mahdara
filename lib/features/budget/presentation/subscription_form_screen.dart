import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';

class SubscriptionFormScreen extends StatefulWidget {
  final AuthService authService;
  final AppSubscription? existingSub;
  final BudgetService? budgetService;

  const SubscriptionFormScreen({
    super.key,
    required this.authService,
    this.existingSub,
    this.budgetService,
  });

  @override
  State<SubscriptionFormScreen> createState() => _SubscriptionFormScreenState();
}

class _SubscriptionFormScreenState extends State<SubscriptionFormScreen> {
  late final BudgetService _budget;
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notifyCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _budget = widget.budgetService ?? BudgetService(widget.authService);
    final s = widget.existingSub;
    if (s != null) {
      _nameCtrl.text = s.name;
      _amountCtrl.text = s.amount.toStringAsFixed(2);
      _notifyCtrl.text = s.notifyDaysBefore.toString();
      _startDate = s.startDate;
      _endDate = s.endDate;
    } else {
      _notifyCtrl.text = '3';
      final now = DateTime.now();
      _startDate = now;
      _endDate = DateTime(now.year, now.month + 1, now.day);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _notifyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final init = isStart
        ? (_startDate ?? now)
        : (_endDate ?? _startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    final notify = int.tryParse(_notifyCtrl.text.trim()) ?? 3;

    if (name.isEmpty || name.length > 80) {
      setState(() => _error = 'اسم الاشتراك مطلوب (1–80 حرف)');
      return;
    }
    if (amount == null || amount < 0) {
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
    if (notify < 0 || notify > 30) {
      setState(() => _error = 'أيام الإشعار يجب أن تكون بين 0 و 30');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final BudgetOverview overview;
      final sub = widget.existingSub;
      if (sub != null) {
        overview = await _budget.updateSubscription(
          subscriptionId: sub.id,
          name: name,
          amount: amount,
          startDate: _startDate!,
          endDate: _endDate!,
          notifyDaysBefore: notify,
          isActive: sub.isActive,
        );
      } else {
        overview = await _budget.addSubscription(
          name: name,
          amount: amount,
          startDate: _startDate!,
          endDate: _endDate!,
          notifyDaysBefore: notify,
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
    if (m.contains('name invalid')) return 'اسم الاشتراك غير صالح';
    if (m.contains('amount')) return 'المبلغ يجب أن يكون صفر أو أكثر';
    if (m.contains('end_date')) {
      return 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية';
    }
    if (m.contains('notify')) return 'أيام الإشعار يجب أن تكون بين 0 و 30';
    if (m.contains('invalid session')) {
      return 'انتهت جلستك — يرجى إعادة تسجيل الدخول';
    }
    return 'حدث خطأ: $msg';
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingSub != null;
    return ZadScaffold(
      title: 'الاشتراكات',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TipCard(
            'أضف الاشتراكات الثابتة مثل العشاء أو الماء ليتم خصمها من الميزانية.',
          ),
          if (_error != null)
            ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
          TextField(
            controller: _nameCtrl,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'اسم الاشتراك',
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
            controller: _notifyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'إشعار قبل (أيام)'),
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
                : Text(isEdit ? 'تحديث الاشتراك' : 'حفظ الاشتراك'),
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
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

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
