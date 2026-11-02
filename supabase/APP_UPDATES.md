# Android mandatory updates

The migration `app_update_policy.sql` is already applied to the linked project,
with enforcement disabled. App clients can read the policy but cannot change it.

The app compares its actual installed Android build number with `minimum_build`.
An enabled policy blocks strictly older builds for every account role and route.
Checks run on startup, resume, and every five foreground minutes.
The update button opens the HTTPS distribution link; it does not install silently.

## Release safely

1. Distribute build 11 (1.0.9), the first release containing this feature.
   Builds 10 and older cannot be forced remotely by this new feature.
2. For a subsequent release, use a build number above the highest uploaded to Play.
3. Publish it and confirm ALL affected users can download it. Closed-test users
   must be enrolled; staged rollouts may not yet offer the update to everyone.
4. Only then raise the minimum in Supabase SQL Editor. Example AFTER build 12 is available:

```sql
update public.app_update_policy
set enabled = true, minimum_build = 12, updated_at = now()
where platform = 'android';
```

Emergency disable:

```sql
update public.app_update_policy
set enabled = false, updated_at = now()
where platform = 'android';
```

You can set `update_url` to another trusted HTTPS distribution page if not using Play.
Never require a build that affected users cannot download.

## Connectivity and scope

On Android, startup first checks the server. During a network failure only, a
previously successful allowed policy may be used for up to seven days alongside
a matching, previously verified active employee/company offline grant. First login,
missing/expired caches, and confirmed access denials still require connectivity.
A known required update stays blocked even offline. Clock rollback beyond five
minutes invalidates an otherwise allowed cached grant/policy.
The sync engine always requires a fresh server policy check before uploading.
After a successful check, transient background failures retain the last decision.
A known mandatory update stays blocked even if a subsequent check fails.
Emergency changes take effect on the next successful check. There is no permanent cache.
This is an app UI gate, not database authorization or protection against modified clients.
Existing RLS and company/account checks are unchanged.

## Verify

Run `flutter analyze`, `flutter test`, and the rolled-back permission checks in
`supabase/tests/app_update_policy_test.sql`.
Test blocking in a dedicated environment by requiring a build one above the installed
version, then disable enforcement again. Do not block shared production users for testing.
