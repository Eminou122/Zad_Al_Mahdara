import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/zad_tokens.dart';
import '../../../features/teams/domain/team_models.dart';
import '../../../services/auth_service.dart';
import '../data/student_directory_service.dart';
import '../domain/student_directory_models.dart';

class StudentDirectoryScreen extends StatefulWidget {
  final AuthService authService;
  final StudentDirectoryService? service;
  const StudentDirectoryScreen({
    super.key,
    required this.authService,
    this.service,
  });
  @override
  State<StudentDirectoryScreen> createState() => _StudentDirectoryScreenState();
}

class _StudentDirectoryScreenState extends State<StudentDirectoryScreen> {
  late final StudentDirectoryService s;
  List<AvailablePublicTeam> teams = [];
  bool loading = true;
  bool error = false;
  @override
  void initState() {
    super.initState();
    s = widget.service ?? StudentDirectoryService(widget.authService);
    unawaited(load());
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await s.getAvailablePublicTeams();
      if (mounted) {
        setState(() {
          teams = r.items;
          loading = false;
          error = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = true;
        });
      }
    }
  }

  Future<void> contact(AvailablePublicTeam t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _Contact(s, t),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال رسالتك إلى مسؤول المجموعة')),
      );
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('الفرق المتاحة')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ZadTokens.contentMaxWidth,
          ),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: load,
                  child: teams.isEmpty
                      ? _State(
                          error
                              ? 'تعذر تحميل الفرق المتاحة'
                              : 'لا توجد فرق متاحة حاليًا',
                          load,
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(ZadTokens.s4),
                          itemCount: teams.length,
                          itemBuilder: (_, i) =>
                              _Card(teams[i], () => contact(teams[i])),
                        ),
                ),
        ),
      ),
    ),
  );
}

class _State extends StatelessWidget {
  final String text;
  final Future<void> Function() refresh;
  const _State(this.text, this.refresh);
  @override
  Widget build(BuildContext c) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      SizedBox(
        height: 400,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text),
              OutlinedButton(
                onPressed: () => unawaited(refresh()),
                child: const Text('تحديث'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  final AvailablePublicTeam t;
  final VoidCallback contact;
  const _Card(this.t, this.contact);
  @override
  Widget build(BuildContext c) => Card(
    child: Padding(
      padding: const EdgeInsets.all(ZadTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.name, style: Theme.of(c).textTheme.titleMedium),
          Text(teamTypeLabels[t.teamType] ?? t.teamType),
          if (t.note != null) Text(t.note!),
          if (t.leaderDisplayName != null)
            Text('مسؤول المجموعة: ${t.leaderDisplayName}'),
          Text('عدد الأعضاء: ${t.memberCount}'),
          const SizedBox(height: ZadTokens.s2),
          if (t.isCurrentMember)
            const Text('أنت عضو في هذه المجموعة')
          else
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: contact,
                child: const Text('تواصل مع مسؤول المجموعة'),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Contact extends StatefulWidget {
  final StudentDirectoryService s;
  final AvailablePublicTeam t;
  const _Contact(this.s, this.t);
  @override
  State<_Contact> createState() => _ContactState();
}

class _ContactState extends State<_Contact> {
  final c = TextEditingController();
  bool busy = false;
  String? e;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final b = c.text.trim();
    if (b.isEmpty || b.length > 500) {
      setState(() => e = b.isEmpty ? 'اكتب رسالة أولاً' : 'الرسالة طويلة جدًا');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.s.contactAvailableTeamLeader(
        teamId: widget.t.teamId,
        body: b,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          e = 'تعذر إرسال الرسالة، حاول مرة أخرى';
        });
      }
    }
  }

  @override
  Widget build(BuildContext x) => AlertDialog(
    title: Text(widget.t.name),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('سيتم إرسال رسالتك إلى مسؤول المجموعة'),
        TextField(
          controller: c,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: InputDecoration(errorText: e),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(x),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: busy ? null : send, child: const Text('إرسال')),
    ],
  );
}
