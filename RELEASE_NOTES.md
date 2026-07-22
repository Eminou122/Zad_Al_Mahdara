# Zad Al-Mahdara — Accepted Production Release

## Verified completion

- Budget updates are smooth without broad reloads.
- Recurring-purchase cancellation is safe and retains history.
- Previous recurring expenses are manageable from آخر المصروفات.
- Whole recurring purchases can be removed while retaining prior history.
- The expense form is simplified.
- Subscription reminders use the improved calm renewal wording.
- Reminder times display Arabic ص / م.
- Login and registration support keyboard navigation.
- Team shopping uses cleaned units and supports required custom units.
- Teams support safe archive, restore, and permanent-removal rules.
- Flutter tests: 586 passed.
- SQL tests: 248 passed.
- Migrations are aligned through 043.
- Production deployment is Ready.
- Owner manual production acceptance: PASS.

## Rollback

- Accepted commit SHA: `e4bb1c6cb318605e113f41d0fbd7fea46d950429`
- Migration level: `043`
- Do not roll back applied migrations destructively. Use a forward corrective migration if a database change is required.
