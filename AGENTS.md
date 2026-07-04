# Zad Al-Mahdara — Agent Instructions

## Language rule

Write all assistant reports in English only.

Arabic is allowed only for exact app UI labels, route labels, button labels, or user-facing text copied from the app.

## Project

Project name:
Zad Al-Mahdara — زاد المحظرة

Production:
https://zad-al-mahdara.vercel.app

Supabase project ref:
secddleiybltnatpzeeo

Supabase URL:
https://secddleiybltnatpzeeo.supabase.co

Local path:
C:\Users\Eminou Habiboullah\Projects\Zad_Al_Mahdara

Because the Windows path contains spaces, always quote it in commands.

PowerShell:
cd "C:\Users\Eminou Habiboullah\Projects\Zad_Al_Mahdara"

Git Bash:
cd "/c/Users/Eminou Habiboullah/Projects/Zad_Al_Mahdara"

## Stack

Flutter Web / PWA
Supabase Postgres
Custom PIN authentication
RPC-only frontend access
Vercel deployment from GitHub main

## Auth architecture

This app does NOT use Supabase Auth.

Do not use:
- auth.uid()
- Supabase Auth sessions
- direct frontend table reads

The app uses:
- profiles
- app_sessions
- custom session_token
- localStorage key: zad_session_token
- client.rpc(...) calls only

Never expose:
- service-role key
- pin_hash
- code_hash
- full phone_number
- plaintext PIN
- reset code except the one-time admin issue dialog

## Database/security rules

RLS must remain enabled.
Direct table grants must remain revoked.
Frontend must not use client.from() table access.
All user-facing data access must go through RPCs.
Admin RPCs must validate custom session_token server-side.
Never use auth.uid().
Never commit secrets.
Never print secrets.

## Git safety

Never stage or commit:
- build/web
- .env files
- design_refs
- supabase/.temp
- service-role keys
- local test env files
- unrelated files

Before commit, always run:
flutter analyze
flutter test
flutter build web --release

Before commit, always inspect:
git status
git diff
git diff --cached

Only stage explicitly expected files.

## Supabase migration rules

Never run db push casually.

Before running db push:
1. Run migration list.
2. Confirm local and remote history are aligned.
3. Confirm only the intended migration is pending.
4. If mismatch appears, STOP and report.

Never edit an already-applied migration unless the owner explicitly instructs and remote patching is handled safely.

For new backend work:
- create a new numbered migration
- test remotely with SQL/RPC smoke tests
- commit migration file immediately after remote apply

## Gate workflow

Work in gates.

For every gate:
1. Inspect current state.
2. Plan before coding.
3. Implement minimal scoped change.
4. Run commands:
   - flutter analyze
   - flutter test
   - flutter build web --release
5. Do manual QA if browser/credentials available.
6. Report clearly.
7. Do not commit/deploy unless the gate explicitly asks for commit/deploy.

Do not move to the next feature until the current gate passes.

## Reporting format

Every report should include:
1. Current HEAD
2. Files changed
3. What changed
4. Commands result
5. Manual QA result
6. Safety inspection
7. Bugs/risks found
8. PASS/FAIL recommendation

If something was not tested, say NOT TESTED.
Do not invent browser QA.

## Design identity

Arabic/RTL-first.
Mobile-first.
Old phones and low bandwidth matter.

Visual identity:
Mahdari Oasis:
- warm cream/sand
- deep Mauritanian green
- restrained gold
- calm, premium, readable

Do not redesign randomly.
Keep changes consistent with existing UI.

## Current live status

Latest known production status:
- Admin panel is live.
- Premium swipe navigation is live.
- Admin masked phone LTR fix is live.
- iOS-inspired navigation motion tuning is live.
- PIN reset backend migration 016 is committed and applied remotely.
- PIN reset frontend/admin UI is implemented locally and manually QA passed, but not yet committed/deployed.

Latest known commit:
5826cc5 — Gate 27.1 PIN reset backend

Local pending Gate 27.2 frontend files may include:
- lib/services/auth_service.dart
- lib/core/routing/app_router.dart
- lib/core/widgets/zad_section_header.dart
- lib/features/auth/presentation/forgot_pin_screen.dart
- lib/features/auth/presentation/reset_pin_screen.dart
- lib/features/admin/data/admin_models.dart
- lib/features/admin/data/admin_service.dart
- lib/features/admin/presentation/admin_screen.dart
- test/admin_models_test.dart
- test/admin_screen_test.dart
- test/pin_reset_flow_test.dart

## Current next task

Before committing/deploying Gate 27.2, verify Vercel production env:

Required:
- SUPABASE_URL exactly:
  https://secddleiybltnatpzeeo.supabase.co
- SUPABASE_ANON_KEY must exist, must not be empty, and must not be service-role.

Do not print secrets.
Do not use service-role key.
Only use anon/publishable key for frontend.

After env verification passes, Gate 27.3 can commit/deploy PIN reset frontend.

## Important feature rules

PIN reset:
- User forgot PIN request must not reveal whether phone exists.
- Admin list must show masked phone only.
- Reset code appears only once in issue dialog.
- Reset code must not be stored in localStorage.
- PIN/code fields must not be logged.
- New PIN must be user-chosen.
- Old sessions are revoked by backend after successful reset.

Admin:
- Admin can view safe user data only.
- Admin cannot deactivate admin users.
- Normal users cannot access /admin.
- Admin masked phones must render LTR.

Navigation:
- Swipe applies only to root bottom-nav tabs.
- Detail/form/auth routes must not swipe.
- Normal users cannot swipe into /admin.
- Browser back and refresh must remain route-based.

## Final instruction

Be conservative.
If unsure, stop and report.
Do not batch risky changes.
Do not commit or deploy unless explicitly requested.
