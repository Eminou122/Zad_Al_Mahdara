---
name: mahdara-browser-qa
description: Run real-user browser QA for Zad Al-Mahdara with Playwright Interactive. Use after automated tests for any Gate involving user-visible Flutter Web behavior, responsive layout, routing, forms, authentication, console errors, or network failures.
---

# Mahdara Browser QA

Test only the current Gate through visible browser interactions. Never treat unit or widget tests as browser QA.

## Workflow

1. Confirm the Gate scope, target URL, allowed test data, and authentication availability.
2. Launch the repository's established Flutter Web command or connect to an already-running app. Use an isolated port and pass secrets only through owner-supplied environment variables or command environment; never print them.
3. Use Playwright Interactive to open the app and interact like a real user: navigate, click, type, submit, reload, and go back.
4. Verify user-visible results, including loading, error, empty, and success states where applicable, not only DOM presence or internal state.
5. Exercise the required flow on desktop and at `320x800`.
6. Inspect browser console errors and failed network requests for every tested flow.
7. Capture screenshots only when useful, typically for failures, and delete them after reporting unless the owner explicitly authorizes committing them.
8. Report each flow as PASS, FAIL, NOT TESTED, or BLOCKED. A full product PASS requires the required real-browser flows.

## Safety

- Limit testing to the current Gate.
- Use only disposable test data and avoid changing application state beyond it.
- Never use private administrator credentials.
- Use only an already-authenticated dedicated browser profile, owner-supplied environment variables, or a dedicated non-admin test account.
- Never put credentials in prompts, screenshots, files, logs, commands shown in reports, or Git.
- Mark authenticated QA BLOCKED when safe authentication is unavailable.
- Stop before destructive, production-mutating, or ambiguous actions and ask the owner.
- Never commit screenshots or other QA artifacts without explicit authorization.
