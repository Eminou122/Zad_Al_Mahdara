import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/zad_info_banner.dart';
import '../../../services/auth_service.dart';
import '../data/team_messaging_service.dart';

const int _maxTitleLength = 120;
const int _maxBodyLength = 3000;

class ComposeTeamAnnouncementScreen extends StatefulWidget {
  final AuthService authService;
  final String teamId;
  final String? teamName;
  final TeamMessagingService? service;

  const ComposeTeamAnnouncementScreen({
    super.key,
    required this.authService,
    required this.teamId,
    this.teamName,
    this.service,
  });

  @override
  State<ComposeTeamAnnouncementScreen> createState() =>
      _ComposeTeamAnnouncementScreenState();
}

class _ComposeTeamAnnouncementScreenState
    extends State<ComposeTeamAnnouncementScreen> {
  late final TeamMessagingService _svc;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? TeamMessagingService(widget.authService);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'لا يمكن نشر إعلان فارغ');
      return;
    }
    if (title.length > _maxTitleLength) {
      setState(() => _error = 'العنوان طويل جدًا (الحد الأقصى 120 حرف)');
      return;
    }
    if (body.length > _maxBodyLength) {
      setState(() => _error = 'الإعلان طويل جدًا (الحد الأقصى 3000 حرف)');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _svc.createTeamAnnouncement(
        teamId: widget.teamId,
        body: body,
        title: title.isEmpty ? null : title,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم نشر الإعلان')));
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = userErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعلان جديد')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ZadTokens.contentMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ZadTokens.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleCtrl,
                    maxLength: _maxTitleLength,
                    enabled: !_submitting,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                  ),
                  const SizedBox(height: ZadTokens.s2),
                  TextField(
                    controller: _bodyCtrl,
                    maxLength: _maxBodyLength,
                    maxLines: 8,
                    minLines: 4,
                    enabled: !_submitting,
                    decoration: const InputDecoration(labelText: 'نص الإعلان'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: ZadTokens.s2),
                    ZadInfoBanner(_error!, kind: ZadBannerKind.danger),
                  ],
                  const SizedBox(height: ZadTokens.s3),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('نشر الإعلان'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
