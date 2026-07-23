import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/zad_confirm.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';
import '../data/team_turn_service.dart';
import '../domain/team_models.dart';
import '../domain/team_turn_models.dart';

/// Minimal, no-login page opened from a manual member's WhatsApp link.
/// Reachable while signed out; never shows anything beyond the four fields
/// the backend RPC returns for a valid, unused, unexpired token.
class DailyRolePublicConfirmScreen extends StatefulWidget {
  final String? token;
  final TeamTurnService? turnService;

  const DailyRolePublicConfirmScreen({super.key, this.token, this.turnService});

  @override
  State<DailyRolePublicConfirmScreen> createState() =>
      _DailyRolePublicConfirmScreenState();
}

class _DailyRolePublicConfirmScreenState
    extends State<DailyRolePublicConfirmScreen> {
  late final TeamTurnService _svc;
  PublicRoleConfirmation? _result;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _svc = widget.turnService ?? TeamTurnService(AuthService());
    _load();
  }

  Future<void> _load() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _result = const PublicRoleConfirmation(status: 'invalid');
        _loading = false;
      });
      return;
    }
    try {
      final r = await _svc.getPublicRoleConfirmation(token);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = userErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    final token = widget.token;
    if (token == null || _submitting) return;
    final ok = await zadConfirm(
      context,
      title: 'تأكيد إكمال دور اليوم',
      body: 'سيتم تسجيل إكمالك لدور اليوم في هذا الفريق.',
      confirmLabel: 'تم إكمال دور اليوم',
    );
    if (!ok) return;
    setState(() => _submitting = true);
    try {
      final r = await _svc.completePublicRoleConfirmation(token);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = userErrorText(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تأكيد دور اليوم')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ZadTokens.contentMaxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.all(ZadTokens.s4),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _content(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_error != null) {
      return ZadInfoBanner(_error!, kind: ZadBannerKind.danger);
    }
    final r = _result;
    if (r == null) {
      return const ZadInfoBanner(
        'تعذر تحميل الرابط',
        kind: ZadBannerKind.danger,
      );
    }
    switch (r.status) {
      case 'invalid':
        return const ZadInfoBanner(
          'هذا الرابط غير صالح.',
          kind: ZadBannerKind.danger,
        );
      case 'expired':
        return const ZadInfoBanner(
          'انتهت صلاحية هذا الرابط.',
          kind: ZadBannerKind.warning,
        );
      case 'used':
        return const ZadInfoBanner(
          'تم استخدام هذا الرابط مسبقاً.',
          kind: ZadBannerKind.info,
        );
      case 'completed':
        return const ZadInfoBanner(
          'تم تسجيل إكمال دور اليوم بنجاح.',
          kind: ZadBannerKind.success,
        );
      case 'ready':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detailRow('العضو', r.memberName ?? ''),
            _detailRow('الفريق', r.teamName ?? ''),
            _detailRow('التاريخ', r.turnDate ?? ''),
            _detailRow(
              'الوجبة',
              teamTypeLabels[r.teamType] ?? dailyRoleMealWord(r.teamType),
            ),
            const SizedBox(height: ZadTokens.s4),
            ElevatedButton(
              onPressed: _submitting ? null : _confirm,
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تم إكمال دور اليوم'),
            ),
          ],
        );
      default:
        return const ZadInfoBanner(
          'حالة غير معروفة',
          kind: ZadBannerKind.danger,
        );
    }
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: ZadTokens.s2),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: ZadTokens.textMuted)),
        const SizedBox(width: ZadTokens.s2),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
