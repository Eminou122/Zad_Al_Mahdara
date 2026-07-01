# Project Notes — زاد المحظرة

## Rules (never break these)

- **Arabic-first**: all UI labels in Arabic. RTL layout everywhere.
- **Old-phone friendly**: target Android 5+, 1 GB RAM, 3G. No heavy libs, no heavy animations.
- **Minimal approach (Ponytail)**: smallest working diff. No speculative abstractions.
- **Never expose secrets**: no hardcoded Supabase URL or anon key in committed code.
- **PIN not password**: user-facing label is "الرمز السري", never "كلمة المرور".

## Auth design (Gate 3+)

- UI shows 8-digit Mauritanian phone + 4-digit PIN.
- **No Supabase Auth** — no email, no SMTP, no synthetic emails.
- Custom PIN auth via PostgreSQL RPC functions: `register_student`, `login_student`,
  `get_current_profile_by_session`, `revoke_session`.
- PIN stored as bcrypt hash server-side. Never stored or logged in plaintext.
- Session token: 32 random bytes hex, SHA-256 hash stored in DB, raw token in localStorage.
- Admin phone: `49413435` — `is_admin = true` set server-side in SQL; cannot be spoofed by client.
- Login locked for 5 minutes after 5 failed attempts.
- Login errors are generic (do not reveal whether phone exists).

## Security notice — MVP only

- 4-digit PIN is convenient but weak. Lockout is the primary brute-force protection.
- `localStorage` session token is readable by JavaScript — acceptable for PWA MVP.
- Do not store or log PINs, session tokens, or Supabase keys in source code.
- Use `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` at build time.
- Before production scale: consider stronger PIN policy, rate-limiting at the PostgREST
  layer, and a more secure session storage strategy.

## Budget rule

- Team shopping cost deducted **only after leader approval**, not on submit.

## What NOT to build in MVP

- Chat
- Push notifications (native)
- Custom font loading (use system Arabic default)
- Riverpod / complex state management
- Heavy image assets
- WASM build target

## Budget formula (Gate 4+)

- `actual_spent` = sum of expenses where source in ('manual', 'recurring_purchase') linked to the active plan
- `subscription_total` = sum of active subscriptions whose period overlaps the budget period
- `remaining_money` = total_money − actual_spent − subscription_total (can be negative)
- `safe_daily_limit` = remaining_money / max(days_remaining, 1)
- `today_spending` = sum of manual + recurring_purchase expenses for today
- `is_over_daily_limit` = today_spending > safe_daily_limit AND days_remaining > 0

Subscriptions are never inserted into expenses. They are tracked in a separate `subscriptions` table.
Recurring purchases are planned only until marked "تم الشراء"; purchased occurrences create one real `expenses` row, skipped occurrences do not deduct.

## Applying migrations

### 001_auth_profiles.sql
**WARNING: contains DROP TABLE CASCADE — destroys all profiles and sessions.**
Only apply to a fresh dev DB before any real users exist. Never re-run after registration.

### 002_budget_foundation.sql
Drops and recreates budget_plans, expenses, subscriptions only.
Safe to re-run on dev DB (destroys budget data, NOT auth data).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.

## Manual tests (Gate 4)

After applying 002_budget_foundation.sql in Supabase SQL Editor:

1. Log in. Navigate to ميزانيتي.
2. Tap "إعداد الميزانية" → enter amount + dates → save. Verify overview shows correct remaining + daily limit.
3. Tap "إضافة مصروف" → fill fields → save. Verify today_spending and remaining update.
4. Edit expense (pencil icon) → change amount → save. Verify totals update.
5. Delete expense (trash icon) → confirm. Verify expense removed.
6. Tap "إضافة اشتراك" → fill fields → save. Verify subscription_total updates.
7. Deactivate subscription (cancel icon) → confirm. Verify it disappears from list.
8. Try adding expense with date outside budget range → expect Arabic error.
9. Add enough expenses to go over daily limit → expect warning banner.

## Team rules (Gate 5+)

- Leader is always position 1; cannot be deactivated via `deactivate_team_member`.
- Private teams: non-members see "team not found or access denied" from `get_team_detail`.
- `search_students_for_team` returns `phone_masked` only — never `phone_number`.
- Membership uniqueness enforced by partial unique index (one active membership per profile per team).

## Applying migrations

### 003_team_foundation.sql
Drops and recreates teams, team_members only.
Safe to re-run on dev DB (destroys team data, NOT auth or budget data).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on `current_profile_id_from_session` from 002_budget_foundation.sql — apply 002 first.

## Manual tests (Gate 5)

After applying 003_team_foundation.sql:

1. Log in. Navigate to الفرق.
2. Tap + → create a public team → verify it appears in "فرقي" and "الفرق العامة".
3. Tap team card → view detail → verify leader shown, member count = 1.
4. Tap "إضافة عضو" → search (min 2 chars) → add another student → verify member count = 2.
5. Tap remove icon on member → confirm → verify member removed.
6. Try removing leader → expect error (blocked server-side).
7. Create a private team → log in as different user → try navigating to /teams/:id → expect access denied message.
8. Tap "تعديل" → change team name/status → save → verify update reflected.

## Turn rules (Gate 6+)

- Leader manually starts today's turn via "بدء دور اليوم". No auto/cron turn creation.
- One pending turn per team at a time. If yesterday is pending, leader must complete it before starting today's.
- Turn advancement uses `team_members.position` (ascending). Inactive members are skipped.
- After `complete_team_turn`: `teams.last_completed_position` = completed position; `teams.current_position` = next active position (with wrap).
- Private non-members and public non-members cannot see turn details (get_team_turn_state enforces this).
- Deactivated members' historical turns remain in `team_turns`; leader can still complete them.
- **Not implemented yet**: shopping checklist, daily tax, payment tracking, messages, notifications, cron, subscription renewal.

## Applying migrations

### 004_team_turn_foundation.sql
Additive-only. Does NOT drop or modify any existing tables.
Safe to apply on top of existing data (uses `if not exists`).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001, 002, 003 already applied.

## Manual tests (Gate 6)

After applying 004_team_turn_foundation.sql:

1. Log in as leader. Open team detail. Verify "دور اليوم" card appears with "لا يوجد دور لهذا اليوم." and "بدء دور اليوم" button.
2. Tap "بدء دور اليوم". Verify "المسؤول اليوم" shows first active member. Verify "التالي" shows next member.
3. Log in as a regular member. Open same team. Verify turn visible but no "بدء" or "تم إنجاز" buttons.
4. Log in as leader. Tap "تم إنجاز الدور". Verify "المسؤول اليوم" disappears (or shows completed), "التالي" updates to next person. History shows the completed turn with ✓.
5. Try tapping "بدء دور اليوم" again the same day → should return same state (idempotent).
6. Move to next day (or temporarily test with a different date). Verify no turn exists, then start again → should pick next member in rotation.
7. Deactivate a member mid-rotation. Start new turn → verify deactivated member is skipped.
8. Try accessing turn state as public non-member → verify only "تفاصيل الأدوار تظهر لأعضاء الفريق فقط." shown.
9. Try `ensure_today_turn` / `complete_team_turn` as non-leader → expect Arabic error in snackbar.
10. Leave a turn pending, try starting next day → expect "أكمل الدور السابق أولاً" error.

## Member lifecycle (Gate 6.1+)

- Two separate actions replace the old single remove/deactivate action:
  - **تعطيل (deactivate)**: `is_active = false`, `removed_at` stays null. Member stays
    visible in team detail labeled "غير نشط", is skipped by turn selection, old turn
    history stays valid.
  - **إزالة (remove)**: `is_active = false`, `removed_at = now()`. Member disappears
    from the team detail member list. The `team_members` row is never hard-deleted, so
    `team_turns.member_id` references and old turn history keep working.
- `deactivate_team_member` and `remove_team_member` are both leader-only and both
  refuse to act on the leader row.
- `get_team_detail` member list/count now key off `removed_at is null` (not `is_active`),
  so a deactivated-but-not-removed member still appears.

## Applying migrations

### 005_member_status_fix.sql
Additive-only. Does NOT modify 001, 002, 003, or 004. Never hard-deletes `team_members`
rows. Safe to re-apply (`if not exists` / `create or replace`).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001–004 already applied.

## Manual tests (Gate 6.1)

After applying 005_member_status_fix.sql:

1. Deactivate an active member (تعطيل): verify the row now shows "غير نشط" in team
   detail, `is_active` is false, `removed_at` is null, and the member is skipped when
   starting the next turn. Old turn history entries for that member still show correctly.
2. Remove an inactive member (إزالة on an already-deactivated row): verify the member
   disappears from the team detail member list, the row still exists in the DB, and
   `removed_at` is not null.
3. Remove an active member directly (إزالة without deactivating first): verify the
   member disappears from the list, `is_active` is false, and `removed_at` is not null.
4. Confirm a non-leader cannot call `deactivate_team_member` or `remove_team_member`
   (expect a leader-only error).
5. Confirm the leader cannot be deactivated or removed (expect "cannot remove the team
   leader").
6. Confirm old turn history still displays the correct member names after both
   deactivation and removal.

## Member lifecycle (Gate 6.2+)

Deactivated no longer means gone for good — it means temporarily absent (e.g. a
student went home to family for a few days). Lifecycle rule split used everywhere:

- **Team access / membership visibility** = `removed_at is null`. An inactive
  (deactivated-but-not-removed) member keeps full team access: private team detail,
  turn state, and turn history all stay visible to them.
- **Leader management permission** = `role = 'leader' and is_active = true and
  removed_at is null`.
- **Turn eligibility** = `is_active = true and removed_at is null`.
- **History joins** = no `removed_at` filter, ever — old turns must keep showing
  removed members' names.

- `get_team_detail`, `get_team_turn_state`, `get_team_turn_history` membership checks
  now only require `removed_at is null` (not `is_active = true`), so an inactive
  member is not locked out of their own team.
- New **تفعيل (reactivate)**: leader-only, brings an inactive (non-removed) member
  back — `is_active = true`, `deactivated_at = null`. Same `team_members.id`/position,
  so it slots straight back into the turn rotation and its old history stays intact.
- `add_team_member`'s duplicate check now rejects any non-removed row (active or
  inactive), not just active ones — you can't double-add someone who is merely
  deactivated. A previously *removed* row does not block re-adding.

## Applying migrations

### 005_member_status_fix.sql
Additive-only. Does NOT modify 001, 002, 003, or 004. Never hard-deletes `team_members`
rows. Safe to re-apply (`if not exists` / `create or replace`).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001–004 already applied.

### 006_member_reactivation_fix.sql
Additive-only. Does NOT modify 001–005. Never hard-deletes `team_members` rows. Safe
to re-apply (`create or replace`).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001–005 already applied.

### 007_turn_next_member_fix.sql
Additive-only. Does NOT modify 001–006. Never hard-deletes `team_members` rows. Safe
to re-apply (`create or replace`).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001–006 already applied.

### 008_single_active_turn_wrap_fix.sql
Additive-only. Does NOT modify 001–007. Never hard-deletes `team_members` rows. Safe
to re-apply (`create or replace`).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001–007 already applied.

### 009_member_counts_and_reactivation_turn_fix.sql
Additive-only. Does NOT modify 001–008. Never hard-deletes `team_members` rows. Safe
to re-apply (`create or replace`).
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001–008 already applied.

### 010_recurring_purchases_foundation.sql
Additive-only. Does NOT modify 001–009. Adds recurring personal purchases, mark-only
occurrences, `recurring_purchase` expense source, and replaces `get_budget_overview`
to include recurring actual spending.
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001–009 already applied.

### 011_external_students_foundation.sql
Additive-only. Does NOT modify 001–010. Adds accountless external students for team
rotation through RPC-only access: `external_students`, nullable `team_members.profile_id`,
`team_members.external_student_id`, mixed account/external member detail, and same-phone
same-team-type validation.
Apply via: Supabase Dashboard → SQL Editor → paste file → Run.
Depends on 001–010 already applied.

Gate 8 scope:

- External students have display name + unique 8-digit phone, but no login account.
- External students can be added, shown, deactivated, reactivated, removed, and included
  in turn rotation.
- No invitations, accept/reject, chat, notifications, shopping/cook tax, service role,
  Supabase Auth, full-phone RPC returns, or broad table policies.
- Future gate: when a user registers with a matching phone, link `external_students`
  to `profiles` only after careful conflict checks. Gate 8 does not auto-link, merge,
  or convert memberships.

Gate 7 limitations:

- Reminder time is stored and shown in the app only. No push notifications, scheduler, or background jobs.
- Frequencies: daily, every N days, weekly. Monthly recurrence is postponed.
- Recurring purchase plans are expected/planned only; only purchased occurrences affect actual budget.

## Manual tests (Gate 6.2)

After applying 006_member_reactivation_fix.sql:

1. Deactivate a member, then log in as that (now inactive) member: verify their
   private team detail still opens and turn history is still visible.
2. Verify the inactive member does not appear as today's or the next turn holder.
3. Leader taps تفعيل on the inactive member: verify the member becomes active again
   (`is_active = true`, `deactivated_at = null`) and is turn-eligible again.
4. Remove a member (إزالة): verify that member's own access to the private team is
   now denied.
5. Verify a removed member still appears correctly by name in old turn history.
6. Confirm a non-leader cannot call `deactivate_team_member`, `remove_team_member`,
   or `reactivate_team_member` directly (expect a leader-only error).
7. Confirm the leader row cannot be deactivated or removed.
8. Try adding an already-inactive (non-removed) member again via `add_team_member`:
   expect "student is already a member of this team".

## Manual tests (Gate 6.3)

After applying 007_turn_next_member_fix.sql:

1. Deactivate the member currently pointed to by `teams.current_position`: verify the
   next active member appears in the turn card.
2. Remove the member currently pointed to by `teams.current_position`: verify the next
   active member appears in the turn card.
3. Deactivate the displayed next member: verify the next active member after them
   appears.
4. Reactivate a member: verify they become turn-eligible again at the same position.
5. Leave only one active member: verify that member appears as next.
6. Leave no active members: verify the turn card shows
   "لا يوجد أعضاء نشطون للأدوار حالياً".
7. If a pending turn is assigned to a member who becomes inactive, verify that pending
   turn still shows.
8. In that same pending-turn case, verify `next_member` separately shows the next active
   member.
9. Verify old turn history still displays removed/deactivated member names.

## Manual tests (Gate 6.4)

After applying 008_single_active_turn_wrap_fix.sql:

1. Create a two-member team: leader active at position 1, member 2 inactive.
2. Leader starts today's turn, then completes it.
3. Verify `next_member` becomes the leader again.
4. With one active member remaining after deactivate/remove, verify that member appears
   as next.
5. With zero active members, verify the turn card shows
   "لا يوجد أعضاء نشطون للأدوار حالياً".
6. Reactivate member 2 and verify they become eligible again at the same position.
7. Verify old turn history still displays inactive/removed member names.

## Manual tests (Gate 6.5)

After applying 009_member_counts_and_reactivation_turn_fix.sql:

1. Create/open a team with leader + 2 members.
2. Deactivate both normal members and verify:
   - "الأعضاء" = 3
   - "الأعضاء النشطون" = 1
   - "الأعضاء غير النشطين" = 2
   - inactive members remain visible with "غير نشط".
3. Leader completes a turn and verify "التالي" is the leader.
4. Reactivate member at position 2 and verify active count updates and "التالي" becomes
   position 2 when the last completed position was the leader.
5. Reactivate member at position 3 and verify counts update while rotation stays correct.
6. Remove a member and verify total "الأعضاء" decreases, the member is hidden, and old
   history still shows their name.
7. Public non-member can open a public team but does not see the member list.
8. Private non-member is denied.

## Manual tests (Gate 7)

After applying 010_recurring_purchases_foundation.sql:

1. Create daily recurring purchase for 14 days: milk 25 MRU.
2. Verify today's list shows milk.
3. Mark purchased and verify one occurrence row is created.
4. Verify one expense row is created with `source = 'recurring_purchase'`.
5. Verify budget today spending and remaining money update.
6. Mark purchased again and verify no duplicate expense is created.
7. Mark skipped and verify the linked recurring expense is removed and budget updates.
8. Confirm another user cannot read, mark, or update the purchase.
9. Create every-2-days purchase and verify it appears only on matching dates.
10. Create weekly purchase and verify it appears only on the same weekday as start date.
11. Try marking a date outside range and expect failure.
12. Verify reminder time displays in the app, with no push notification.
13. Verify /budget/recurring route refresh works after production deploy.

## Manual tests (Gate 8)

After applying 011_external_students_foundation.sql:

1. Leader adds external student.
2. External student appears in team detail as بدون حساب.
3. External student appears in turn rotation.
4. Start/complete turn with external member.
5. Turn history keeps external display name.
6. Deactivate external member; skipped by turns.
7. Reactivate external member; returns to rotation.
8. Remove external member; hidden from list, history remains.
9. Duplicate external phone rejected/reused safely.
10. Same phone cannot be active/non-removed in two lunch teams.
11. Same phone can be in lunch + dinner.
12. Existing account phone cannot be created as external.
13. Account member cannot be added to two active teams of same type.
14. Team type update blocked if same-phone conflict would happen.
15. Non-leader cannot create/add external student.
16. Public non-member cannot see member list.
17. Private non-member denied.

## Gates

| Gate | Scope |
|---|---|
| 1 | Architecture decisions |
| 2 ✅ | Flutter Web PWA scaffold |
| 3 ✅ | Auth flow (phone + PIN, custom RPC) |
| 4 ✅ | Personal budget foundation |
| 5 ✅ | Team management foundation |
| 6 ✅ | Team turn foundation (manual rotation) |
| 6.1 ✅ | Separate deactivate vs remove member |
| 6.2 ✅ | Temporary absence + reactivation fix |
| 6.3 ✅ | Recompute next turn after deactivate/remove |
| 6.4 ✅ | Single active member turn wrap fix |
| 6.5 ✅ | Member counts + reactivation turn recompute |
| 7 | Deploy to Vercel |
| 8 | External students / accountless team members |
