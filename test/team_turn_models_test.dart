import 'package:flutter_test/flutter_test.dart';
import 'package:zad_al_mahdara/features/teams/domain/team_turn_models.dart';

void main() {
  group('TeamTurnState.fromJson', () {
    test('parses state with active pending turn', () {
      final s = TeamTurnState.fromJson({
        'can_manage_turns': true,
        'today_turn': {
          'id': 'turn-1',
          'turn_date': '2026-07-01',
          'status': 'pending',
          'member_id': 'mem-1',
          'display_name': 'محمد',
          'position': 2,
        },
        'next_member': {
          'member_id': 'mem-2',
          'position': 3,
          'display_name': 'فاطمة',
        },
        'last_completed_turn': null,
        'history': [
          {
            'id': 'turn-0',
            'turn_date': '2026-06-30',
            'status': 'completed',
            'member_id': 'mem-3',
            'display_name': 'أحمد',
            'position': 1,
            'completed_at': '2026-06-30T12:00:00Z',
          },
        ],
      });

      expect(s.canManageTurns, true);
      expect(s.todayTurn?.displayName, 'محمد');
      expect(s.todayTurn?.status, 'pending');
      expect(s.nextMember?.displayName, 'فاطمة');
      expect(s.nextMember?.position, 3);
      expect(s.lastCompletedTurn, isNull);
      expect(s.history.length, 1);
      expect(s.history.first.completedAt, isNotNull);
    });

    test('parses state with no turn today', () {
      final s = TeamTurnState.fromJson({
        'can_manage_turns': false,
        'today_turn': null,
        'next_member': {
          'member_id': 'mem-1',
          'position': 1,
          'display_name': 'خديجة',
        },
        'last_completed_turn': {
          'id': 'turn-5',
          'turn_date': '2026-06-28',
          'status': 'completed',
          'member_id': 'mem-4',
          'display_name': 'عمر',
          'position': 4,
          'completed_at': '2026-06-28T09:00:00Z',
        },
        'history': [],
      });

      expect(s.canManageTurns, false);
      expect(s.todayTurn, isNull);
      expect(s.nextMember?.displayName, 'خديجة');
      expect(s.lastCompletedTurn?.turnDate, '2026-06-28');
      expect(s.history, isEmpty);
    });

    test('parses public non-member empty state', () {
      final s = TeamTurnState.fromJson({
        'can_manage_turns': false,
        'today_turn': null,
        'next_member': null,
        'last_completed_turn': null,
        'history': [],
      });

      expect(s.canManageTurns, false);
      expect(s.todayTurn, isNull);
      expect(s.nextMember, isNull);
      expect(s.lastCompletedTurn, isNull);
      expect(s.history, isEmpty);
    });

    test('parses missed-turn blocking metadata', () {
      final s = TeamTurnState.fromJson({
        'can_manage_turns': true,
        'today_turn': null,
        'next_member': null,
        'last_completed_turn': null,
        'history': [],
        'blocking_previous_turn': true,
        'can_skip_previous_turn': true,
        'blocking_reason': 'previous_turn_pending',
        'previous_turn_id': 'turn-prev',
        'previous_turn_member_name': 'سالم',
        'previous_turn_date': '2026-07-04',
        'previous_turn_status': 'pending',
      });

      expect(s.blockingPreviousTurn, true);
      expect(s.canSkipPreviousTurn, true);
      expect(s.blockingReason, 'previous_turn_pending');
      expect(s.previousTurnId, 'turn-prev');
      expect(s.previousTurnMemberName, 'سالم');
      expect(s.previousTurnDate, '2026-07-04');
      expect(s.previousTurnStatus, 'pending');
    });
  });

  group('TurnEntry.fromJson', () {
    test('handles null completed_at', () {
      final e = TurnEntry.fromJson({
        'id': 'x',
        'turn_date': '2026-07-01',
        'status': 'pending',
        'member_id': 'm1',
        'display_name': 'علي',
        'position': 1,
        'completed_at': null,
      });
      expect(e.completedAt, isNull);
      expect(e.status, 'pending');
    });

    test('parses started and skipped fields', () {
      final e = TurnEntry.fromJson({
        'id': 'x',
        'turn_date': '2026-07-01',
        'status': 'skipped',
        'member_id': 'm1',
        'display_name': 'علي',
        'position': 1,
        'started_at': '2026-07-01T08:00:00Z',
        'started_by': 'profile-1',
        'skipped_at': '2026-07-02T08:00:00Z',
        'skipped_by': 'profile-2',
        'skip_reason': 'غائب',
      });

      expect(e.startedAt, isNotNull);
      expect(e.startedBy, 'profile-1');
      expect(e.skippedAt, isNotNull);
      expect(e.skippedBy, 'profile-2');
      expect(e.skipReason, 'غائب');
    });
  });
}
