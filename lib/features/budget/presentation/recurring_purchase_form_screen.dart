import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/zad_scaffold.dart';
import '../../../core/widgets/tip_card.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';
import '../data/budget_service.dart';
import '../domain/budget_models.dart';

class RecurringPurchaseFormScreen extends StatefulWidget {
  final AuthService authService;
  final RecurringPurchase? existing;
  final BudgetService? budgetService;

  const RecurringPurchaseFormScreen({
    super.key,
    required this.authService,
    this.existing,
    this.budgetService,
  });

  @override
  State<RecurringPurchaseFormScreen> createState() =>
      _RecurringPurchaseFormScreenState();
}

class _RecurringPurchaseFormScreenState
    extends State<RecurringPurchaseFormScreen> {
  late final BudgetService _budget;
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _frequency = 'daily';
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _reminderTime;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _budget = widget.budgetService ?? BudgetService(widget.authService);
    final r = widget.existing;
    if (r == null) {
      final now = DateTime.now();
      _startDate = now;
      _endDate = now.add(const Duration(days: 13));
      _intervalCtrl.text = '2';
      return;
    }
    _nameCtrl.text = r.name;
    _priceCtrl.text = r.price.toStringAsFixed(2);
    _frequency = r.frequency;
    _intervalCtrl.text = (r.intervalDays ?? 2).toString();
    _startDate = r.startDate;
    _endDate = r.endDate;
    _noteCtrl.text = r.note ?? '';
    _reminderTime = _parseTime(r.reminderTime);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _intervalCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: start
          ? (_startDate ?? now)
          : (_endDate ?? _startDate ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _reminderTime = picked);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    final interval = int.tryParse(_intervalCtrl.text.trim());
    final note = _noteCtrl.text.trim();

    if (name.isEmpty || name.length > 80) {
      setState(() => _error = 'اسم الشراء مطلوب (1-80 حرف)');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'أدخل سعراً صحيحاً (صفر أو أكثر)');
      return;
    }
    if (_startDate == null || _endDate == null) {
      setState(() => _error = 'اختر تاريخ البداية والنهاية');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _error = 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية');
      return;
    }
    if (_frequency == 'every_n_days' &&
        (interval == null || interval < 2 || interval > 365)) {
      setState(() => _error = 'عدد الأيام يجب أن يكون بين 2 و 365');
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
      final r = widget.existing;
      if (r == null) {
        final items = await _budget.createRecurringPurchase(
          name: name,
          price: price,
          frequency: _frequency,
          intervalDays: _frequency == 'every_n_days' ? interval : null,
          startDate: _startDate!,
          endDate: _endDate!,
          reminderTime: _timeText(_reminderTime),
          note: note.isEmpty ? null : note,
        );
        if (mounted) context.pop(items);
      } else {
        final items = await _budget.updateRecurringPurchase(
          recurringPurchaseId: r.id,
          name: name,
          price: price,
          frequency: _frequency,
          intervalDays: _frequency == 'every_n_days' ? interval : null,
          startDate: _startDate!,
          endDate: _endDate!,
          reminderTime: _timeText(_reminderTime),
          note: note.isEmpty ? null : note,
        );
        if (mounted) context.pop(items);
      }
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return ZadScaffold(
      title: isEdit ? 'تعديل شراء متكرر' : 'إضافة شراء متكرر',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TipCard('لن يتم خصم المال إلا عند اختيار "تم الشراء".'),
          if (_error != null)
            ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
          TextField(
            controller: _nameCtrl,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'اسم الشراء',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'السعر (MRU)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: 'التكرار'),
            items: const [
              DropdownMenuItem(value: 'daily', child: Text('كل يوم')),
              DropdownMenuItem(
                value: 'every_n_days',
                child: Text('كل عدة أيام'),
              ),
              DropdownMenuItem(value: 'weekly', child: Text('كل أسبوع')),
            ],
            onChanged: (v) => setState(() => _frequency = v ?? 'daily'),
          ),
          if (_frequency == 'every_n_days') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _intervalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد الأيام'),
            ),
          ],
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
          InkWell(
            onTap: _pickTime,
            onLongPress: () => setState(() => _reminderTime = null),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'وقت التذكير (اختياري)',
                suffixIcon: Icon(Icons.schedule_outlined, size: 18),
              ),
              child: Text(_timeText(_reminderTime) ?? 'لا يوجد'),
            ),
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
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(isEdit ? 'تحديث' : 'حفظ'),
          ),
        ],
      ),
    );
  }

  static TimeOfDay? _parseTime(String? value) {
    if (value == null || !value.contains(':')) {
      return null;
    }
    final parts = value.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  static String? _timeText(TimeOfDay? t) => t == null
      ? null
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _arabicError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('name')) {
      return 'اسم الشراء غير صالح';
    }
    if (m.contains('price')) {
      return 'السعر يجب أن يكون صفر أو أكثر';
    }
    if (m.contains('interval')) {
      return 'عدد الأيام غير صالح';
    }
    if (m.contains('end_date')) {
      return 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية';
    }
    if (m.contains('invalid session')) {
      return 'انتهت جلستك — يرجى إعادة تسجيل الدخول';
    }
    return 'حدث خطأ: $msg';
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
