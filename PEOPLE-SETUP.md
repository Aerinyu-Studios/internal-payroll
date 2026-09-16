# Aerinyu People hub and Google Workspace onboarding

The People hub is at `/people` on the same deployment as your finance application, for example `https://finance.aerinyustudios.com/people`. Use the People hub link in the finance sidebar. No additional subdomain or separate database is required.

## Deploy this update

1. Upload the extracted contents of the updated application ZIP to your repository.
2. In Supabase SQL Editor, run `202609160006_employee_role.sql` and let it finish. Run `202609160007_people_hub.sql` as a SEPARATE query afterward. PostgreSQL requires the new role enum to be committed before it is used. Do not combine these two files into one transaction.
3. These migrations assume migrations 001 through 005 are already installed. For a new database, apply every migration in order. Do not rerun previously applied migrations.
4. Deploy the updated commit in Vercel using Next.js, build command `npm run build:next`, and the default output directory with its override off.
5. Open `/people` with your existing administrator account.

The migration preserves personnel, finance records, issued documents and existing employee IDs. It continues the studio-wide employee sequence after 010, or after the highest existing seven-digit ID suffix if that is greater. New IDs use YYZZSSS: hire year, a random two-digit number, and a three-digit sequence. The first new ID ends in 011 when 010 is the highest existing suffix. The sequence never resets by year or after deleting a record. The three-digit format stops at 999 instead of silently changing format.

## What the hub includes

- Searchable staff directory, department and status filters, and a directory CSV export.
- Department heads, teams/units, and an automatically generated reporting chart.
- Administrator-managed employment information and reporting relationships, including cycle prevention.
- Automatic employee IDs and retry-safe onboarding reservations.
- Creation of a company Google account with employee ID, department, title and manager metadata.
- Linking of existing staff to an existing company Google account without changing their email or ID.
- Restricted personal and payment fields. Employees see their own restricted details; administrators see personal details; finance and administrators see payment details.
- Profile-change requests with administrator or finance review. Approved payment details also update the existing finance payment-information panel.
- An onboarding checklist per new hire.
- A limited Employee application role. New employees cannot read the finance workspace or other employees' private details, including through direct database/API access.

Existing free-text payment information is retained. It is not guessed or parsed into the new structured bank fields. Existing personnel phone numbers are copied into the restricted personal profile during migration.

## Connect Google Workspace

Normal employee Google sign-in and administrator account provisioning are separate integrations. Your existing sign-in configuration stays in place. Provisioning requires an administrator-approved Google service account, not broader scopes on every employee's sign-in.

In Google Cloud:

1. Choose the company-owned project and enable the Admin SDK API.
2. Create a dedicated service account for Aerinyu employee onboarding.
3. Enable Google Workspace domain-wide delegation for that service account and note its numeric OAuth client ID.
4. Create a JSON service-account key. Store it securely; do not commit it to Git, upload it to the source ZIP, or paste it into chat.

In Google Admin, using a super administrator:

1. Go to Security > Access and data control > API controls > Manage Domain Wide Delegation.
2. Add the service account's numeric client ID.
3. Authorize exactly this scope:

```
https://www.googleapis.com/auth/admin.directory.user
```

4. Select an existing company administrator account to be impersonated by the integration. It needs the user-management privileges necessary to read and create users. Use the least privileged suitable administrator account.
5. Check your subscription's available licences and automatic licensing settings. Creating an account may consume a paid Workspace seat. The application does not buy licences or guarantee that Gmail is licensed or immediately ready.

In Vercel > Project Settings > Environment Variables, add these SERVER-ONLY values for Production:

| Variable | Value |
| --- | --- |
| `GOOGLE_WORKSPACE_ADMIN_EMAIL` | The delegated company administrator email |
| `GOOGLE_WORKSPACE_SERVICE_ACCOUNT_JSON` | The complete JSON key contents, pasted as one environment-variable value |
| `SUPABASE_SERVICE_ROLE_KEY` | The Supabase server secret/service-role key, used only by server code to prepare Auth accounts |

Keep the existing `SUPABASE_URL` and `SUPABASE_ANON_KEY` variables. Do not replace the anon key with the service-role key. Never use `NEXT_PUBLIC_` for these credentials. Redeploy after adding or changing environment variables.

The onboarding page reports whether the required variables are present. It does not claim that the credentials or delegation have been verified until a real operation succeeds.

## Onboard a new employee

1. Open People hub > Onboard employee.
2. Enter given names, family name, legal/preferred name, department, title, manager and hire date.
3. Review the suggested company email. The username is editable. Existing styles such as `dnpillay`, `vkhoo`, `camile` and `jtheng` are preserved; no global renaming occurs.
4. Save the employee. Their ID is allocated once and appears in the profile.
5. Review the company account section and click Create company account. This creates an actual Google Workspace user and prepares a Supabase Auth account with the limited Employee role.
6. Copy the temporary password shown in the result and hand it to the employee securely. This application neither stores the password nor sends welcome messages. Google requires a password change at first sign-in.
7. Have the employee first sign in to Google and complete Google's account setup. Then they can sign into the People hub with Google.
8. Complete the onboarding checklist and review their submitted personal/payment details.

If a network interruption occurs, retry from the same employee profile. An expiring claim prevents simultaneous attempts, and a Google account marker ties a created account to the immutable personnel UUID. A retry reuses that account and the employee ID. An unrelated existing email address is never silently adopted or overwritten. Resolve address conflicts in Google Admin before retrying.

If Google created the account but the app-access step failed, the UI retains a retry action and displays the new password when it was returned successfully. If that password was lost or the browser response never arrived, reset it in Google Admin. Retrying does not reset an existing account's password.

## Link your existing employees

Open an existing employee's profile and choose Link employee portal access. The app checks that their exact company email is the primary email of an active Google Workspace account. It then prepares or links their Supabase sign-in identity. Existing administrator, finance or manager roles are retained; new accounts receive Employee access.

The account must already exist in Google Admin. Linking does not create a replacement Google account or change its password. Once linked, the employee's My profile page can be used for personal and payment-information requests.

## Access and offboarding

Only an application administrator can onboard employees or create/link Workspace accounts. Company Google sign-in, domain checks and existing administrator-assigned permissions remain mandatory. Keep public Supabase sign-ups disabled; the server creates the Auth record for an approved employee before their first sign-in.

Personal information is excluded from public directory exports. Bank details and birth dates are not sent to Google Workspace. Audit entries record operations and IDs, not the submitted personal or bank field contents.

Marking an employee inactive, suspended or departed disables their linked application profile. This does NOT suspend Google Workspace, Asana, Discord or other external accounts. Suspend/revoke those in the corresponding administrator console and handle files and task ownership there. Setting the employee active again does not automatically reactivate their application profile; an administrator must review access in Finance Administration.

Changes to department, title, manager or name after account creation currently update the People hub. Ongoing Google Directory synchronisation, bulk CSV onboarding, Asana task synchronisation and Slack/Discord provisioning are not part of this release. The hub includes a directory CSV export; the existing finance app continues to use the same personnel records.

## Verification and current limits

- TypeScript checks and Next.js route type generation pass.
- 40 automated tests pass, covering finance regressions, ID allocation, onboarding retries, manager-cycle checks, employee isolation, approval flow, signed Google requests and address-conflict recovery.
- Browser review used a separate localhost-only fictional fixture to inspect the directory, chart and onboarding form. No fictional employees were inserted into the application database or included as production fallback data.
- The native Next.js build was attempted but this Windows execution environment denied a subprocess launch with `spawn EPERM`. Verify the production build on Vercel.
- No live database migrations, Google accounts, DNS records or Vercel deployments were changed from this task. Live account creation and first Google sign-in must be verified after connecting your credentials.

References: [Google Directory user creation](https://developers.google.com/workspace/admin/directory/v1/guides/manage-users), [service accounts and domain-wide delegation](https://developers.google.com/identity/protocols/oauth2/service-account), [Google Directory user fields](https://developers.google.com/workspace/admin/directory/reference/rest/v1/users).
