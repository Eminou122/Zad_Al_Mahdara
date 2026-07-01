# زاد المحظرة — Zad Al-Mahdara

منصة الطلاب والمحاظر الموريتانية | Mauritanian Mahdara student platform.

## Setup

```bash
flutter pub get
```

## Run (web)

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=YOUR_SUPABASE_URL_HERE \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY_HERE
```

Without keys the app launches in demo mode (splash → login screen, no Supabase connection).

## Build (web release)

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=YOUR_SUPABASE_URL_HERE \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY_HERE
```

Output goes to `build/web/`. Deploy that folder to Vercel.

## Environment variables

Never commit secrets. Pass via `--dart-define` or set in Vercel dashboard.

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anon/public key (from Project Settings → API) |

## Auth design — Custom PIN Auth (no Supabase Auth)

Supabase Auth (email/password, OTP, SMTP) is **not used** for students.

Authentication works entirely through PostgreSQL RPC functions:

| RPC | Purpose |
|---|---|
| `register_student(name, phone, pin)` | Create account, return session token |
| `login_student(phone, pin)` | Verify PIN, return session token |
| `get_current_profile_by_session(token)` | Validate session, return profile |
| `revoke_session(token)` | Logout — invalidate session server-side |

- PIN is stored as a bcrypt hash (never raw).
- Session token is 32 random bytes (hex). Only the SHA-256 hash is stored in DB.
- Flutter stores only the raw session token in browser `localStorage`.
- `is_admin` is derived server-side based on `phone_number = '49413435'`. Cannot be spoofed.
- Direct table access is blocked (RLS + revoke). Only RPCs are accessible to `anon`.
- Login is locked for 5 minutes after 5 consecutive wrong PINs.
- Login errors are generic — do not reveal whether the phone number exists.

## Supabase setup (one-time, Gate 3)

**No email setup needed.** Do not enable SMTP or email confirmations.

### 1 — Apply the database migration

Dashboard → SQL Editor → New query → paste the contents of:

```
supabase/migrations/001_auth_profiles.sql
```

Run it. Creates `profiles`, `app_sessions`, RLS, and all 4 RPC functions.

> Re-running drops and recreates the tables. Only safe on a fresh dev DB with no real users.

### 2 — Create the founder account

Run the app with real Supabase keys, go to Register, and enter:

- Phone: `49413435`
- Name: any name
- PIN: private PIN chosen by the founder (do not write it anywhere)

The `register_student` function sets `is_admin = true` server-side for this phone number.
The founder will see "لوحة الإدارة" on the home screen.

## Manual test checklist

1. `flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
2. Register a new account (any 8-digit phone + 4-digit PIN) → auto signed in, go to home
3. Tap "خروج" → session revoked, go to login
4. Sign in again with same phone + PIN → go to home
5. Refresh the page → session restored from localStorage (stay on home)
6. Register founder phone `49413435` → "لوحة الإدارة" tile visible
7. Wrong PIN 5 times → locked for 5 minutes, still shows generic error
8. Try direct table access via Supabase Table Editor while logged in → should be blocked

## MVP security limitations

- 4-digit PIN has only 10,000 combinations. Lockout is the main protection.
- Session token in `localStorage` is readable by JS — acceptable for PWA MVP, not for sensitive data.
- bcrypt cost 8 is fast enough for rate-limited login but would be too weak if hashes were ever exposed.
- Replace or harden auth before scaling beyond 250–300 users or handling sensitive content.

## Old-phone compatibility rule

Target: Android 5+ (2015–2016 phones), 1 GB RAM, weak 3G.
- No heavy animations
- No large image assets
- No complex state libraries
- Large tap targets (min 48×48dp)
- Simple cards, minimal nesting

## Current scope (Gate 3)

- Custom PIN auth: register, login, logout, session persistence
- Route guard: unauthenticated users redirected to login
- Admin route blocked for non-admin users
- `profiles` + `app_sessions` with RLS (server-side admin derivation, no client spoofing)

## Next gate (Gate 4)

Budget module: team budget display, spending requests, leader approval flow.
