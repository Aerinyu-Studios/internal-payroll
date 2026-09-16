# Deploy to finance.aerinyustudios.com

Use the updated `Aerinyu-Studios-application.zip`. It includes `vercel.json`, which selects Next.js and the `npm run build:next` command. Both `npm run build` and `npm run build:next` now run native Next.js. The local/Sites adapter remains available as `npm run build:preview`.

If your Vercel log ends with `vinext start`, it used the preview adapter. Update the repository with this package, select Next.js under Settings > Build and Deployment, use `npm run build:next`, and turn off the Output Directory override. Redeploy the updated commit without the previous build cache. The new log should show `next build --webpack`. Open the new deployment using its Visit button.

## 1. Import the application

Extract the ZIP and put its contents in a private Git repository. Import that repository into Vercel as a new project. Use the directory containing `package.json` as the root directory.

Use these project settings:

| Setting | Value |
| --- | --- |
| Framework | Next.js |
| Node.js | 22.x |
| Install command | `npm ci` |
| Build command | `npm run build:next` |
| Output directory | Leave the Next.js default; do not use `dist` |

Add these environment variables for Production:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
```

Use your existing Supabase project's URL and publishable or anon key. Keep the names exactly as above, without a NEXT_PUBLIC_ prefix. Do not use a service-role key for SUPABASE_ANON_KEY. This finance-only application does not need Google service-account credentials or a Supabase service-role key. Add the variables before deploying, or redeploy after changing them. Your personnel and payment records remain in the same Supabase project.

The existing employee-ID and Google-access migrations are still required if you have not applied them. They are included in `supabase/migrations`; do not rerun migrations already applied to your database.

## 2. Add the finance subdomain

In the Vercel project's Settings, open Domains and add:

```text
finance.aerinyustudios.com
```

Vercel will display the DNS record for this project. At the provider managing your domain's DNS, add:

| Field | Value |
| --- | --- |
| Type | CNAME |
| Name / Host | `finance` |
| Target / Value | Copy the exact target shown by Vercel |
| TTL | Automatic or the provider's default |

Some DNS providers require the full name `finance.aerinyustudios.com` instead of `finance`. Use their name-field convention. Vercel may also request a TXT ownership-verification record; add the exact record it displays if needed. Do not guess the CNAME target, since it can be project-specific.

Only the finance subdomain needs changing. Your main website and Workspace email DNS records can stay as they are. Wait until Vercel reports a valid domain configuration and HTTPS works.

Reference: [Vercel custom-domain setup](https://vercel.com/docs/domains/working-with-domains/add-a-domain).

## 3. Set Google sign-in URLs

In Supabase Authentication, open URL Configuration.

Set **Site URL** to:

```text
https://finance.aerinyustudios.com
```

Add this exact **Redirect URL**:

```text
https://finance.aerinyustudios.com/api/auth/google/callback
```

In Google Auth Platform, open your existing OAuth Web client. Add this **Authorized JavaScript origin**:

```text
https://finance.aerinyustudios.com
```

Keep Google's **Authorized redirect URI** set to the Supabase callback shown in Supabase's Google-provider settings, normally:

```text
https://YOUR_PROJECT.supabase.co/auth/v1/callback
```

The Supabase callback in Google and the app callback in Supabase are different URLs. The allowed account domain remains `aerinyustudios.com`, not `finance.aerinyustudios.com`. Keep the OAuth audience Internal and the app's administrator-assigned roles in place. No extra Google scopes are needed.

References: [Supabase production redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls), [Google-provider setup](https://supabase.com/docs/guides/auth/social-login/auth-google).

## 4. Check the deployed app

Open `https://finance.aerinyustudios.com/login`, complete Google sign-in with your authorized company account, then check personnel, a generated receipt download and a proof attachment.

New proof uploads are limited to 4 MB to fit beneath Vercel's 4.5 MB function request-body limit. Existing larger proofs can still be downloaded: finance-authorized requests receive a private Supabase download link valid for 60 seconds. Buckets remain private. Reference: [Vercel function limits](https://vercel.com/docs/functions/limitations).

The local TypeScript and route tests pass. A native Next.js production build was attempted but stopped when this Windows execution environment denied a subprocess launch (`spawn EPERM`). The Vercel build and live Google sign-in have not been verified. No Vercel project or DNS records were created or changed from this task.

## Finance-only rollback

See FINANCE-ROLLBACK.md. Apply migration 008 to disable retired People RPCs if the People migrations were installed. Account provisioning is removed; only SUPABASE_URL and SUPABASE_ANON_KEY are needed by this application.
