import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/zad_tokens.dart';
import '../../../core/utils/error_text.dart';
import '../data/team_messaging_service.dart';

class MessageTeamLeaderDialog extends StatefulWidget {
  final TeamMessagingService service;
  final String teamId;

  const MessageTeamLeaderDialog({
    super.key,
    required this.service,
    required this.teamId,
  });

  @override
  State<MessageTeamLeaderDialog> createState() =>
      _MessageTeamLeaderDialogState();
}

class _MessageTeamLeaderDialogState extends State<MessageTeamLeaderDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'اكتب رسالة أولاً');
      return;
    }
    if (text.length > 2000) {
      setState(() => _error = 'الرسالة طويلة جداً');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sent = await widget.service.sendMessageToTeamLeader(
        teamId: widget.teamId,
        body: text,
      );
      if (mounted) Navigator.pop(context, sent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = userErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('رسالة إلى قائد الفريق'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            maxLength: 2000,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            enabled: !_sending,
            decoration: const InputDecoration(
              hintText: 'اكتب رسالتك',
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: ZadTokens.s2),
            Text(
              _error!,
              style: const TextStyle(color: ZadTokens.danger, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('إرسال'),
        ),
      ],
    );
  }
}
