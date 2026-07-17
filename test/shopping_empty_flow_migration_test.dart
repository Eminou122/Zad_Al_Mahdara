import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/037_block_empty_shopping_flows.sql',
    ).readAsStringSync();
  });

  test('migration guards dispatch, report transitions, and completion', () {
    expect(sql, contains('enforce_nonempty_shopping_turn_trigger'));
    expect(sql, contains('before insert or update of status'));
    expect(sql, contains('enforce_nonempty_shopping_report_trigger'));
    expect(sql, contains("new.leader_status = 'accepted'"));
    expect(sql, contains("new.status = 'completed'"));
  });

  test('migration requires one active valid item and a report occurrence', () {
    expect(sql, contains('lock_valid_team_shopping_item_count'));
    expect(sql, contains('v_valid_item_count < 1'));
    expect(sql, contains('i.is_active = true'));
    expect(sql, contains("occ.status in ('bought', 'not_bought')"));
    expect(sql, contains('for share'));
  });

  test('migration protects the last item during an active flow', () {
    expect(sql, contains('protect_last_active_shopping_item_trigger'));
    expect(sql, contains("tt.status = 'pending'"));
    expect(sql, contains("r.leader_status = 'pending'"));
  });

  test('migration keeps helpers private and existing RPC contracts intact', () {
    expect(sql, contains('from public, anon, authenticated'));
    expect(sql, isNot(contains('grant execute')));
    expect(
      sql,
      isNot(
        contains(
          'create or replace function public.submit_team_shopping_report',
        ),
      ),
    );
    expect(sql, isNot(contains('auth.uid()')));
  });
}
