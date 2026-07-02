import 'package:flutter/material.dart';
import '../theme/zad_tokens.dart';
import 'zad_logo_badge.dart';

class ZadScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;

  const ZadScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZadLogoBadge(size: 30),
            const SizedBox(width: ZadTokens.s2 + 2),
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: actions,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: ZadTokens.contentMaxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ZadTokens.s4),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
