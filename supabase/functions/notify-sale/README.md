# notify-sale Edge Function

This function sends a Firebase Cloud Messaging notification to the `admins`
topic after a new sale is inserted.

## Required Secrets

Create a Firebase service account from:

Firebase Console > Project settings > Service accounts > Generate new private key

Then set these Supabase Edge Function secrets:

```powershell
supabase secrets set NOTIFY_SALE_SECRET="choose-a-long-random-secret"
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='<paste-service-account-json-here>'
```

Use the same `NOTIFY_SALE_SECRET` value inside:

`supabase/automatic_sale_notifications.sql`

## Deploy

```powershell
supabase functions deploy notify-sale
```

Then check Supabase Dashboard > Edge Functions > notify-sale > Settings and make
sure JWT verification is OFF. The function is still protected by
`NOTIFY_SALE_SECRET`.

After deployment, run:

`supabase/automatic_sale_notifications.sql`

in Supabase SQL Editor.

## Test

1. Install the Android app.
2. Log in as an admin once so the phone subscribes to the `admins` topic.
3. Close the app.
4. Add a sale from an employee account.
5. The admin phone should receive a push notification.
