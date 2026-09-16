# Return to the finance workspace

This reverts the People hub portion of commit 50e9f155a1dc502d32074ff3aab24f6d5a8e1cf1. It retains the native Next.js/Vercel build configuration, 4 MB proof uploads and private document-download fixes from that commit.

Removed: employee portal, organisation chart, onboarding, automatic employee IDs and Google Workspace account provisioning. Existing finance personnel, work records, payments, reports, receipts, Google sign-in, branding and manually assigned employee IDs remain.

## Apply to the existing installation

1. Deploy this commit in the same Vercel project. Build command: npm run build:next. Leave the output directory override off.
2. In Supabase SQL Editor run supabase/migrations/202609160008_retire_people_hub.sql as a complete query. A code deploy alone does not disable database RPCs from the former People hub. The migration is safe with only 001-005 installed, with 006/007 installed, and when rerun.
3. Remove GOOGLE_WORKSPACE_SERVICE_ACCOUNT_JSON, GOOGLE_WORKSPACE_ADMIN_EMAIL and SUPABASE_SERVICE_ROLE_KEY from this Vercel project's environments. Retain SUPABASE_URL and SUPABASE_ANON_KEY. Redeploy after removing the variables.
4. In Google Admin, remove the domain-wide delegation entry for the dedicated Aerinyu Onboarding service account. In Google Cloud, disable its downloaded key and restore the key-creation policy restrictions changed for this experiment. Keep the ordinary Google OAuth sign-in client and Supabase Google provider configuration.
5. Verify company Google sign-in, personnel editing with manual IDs, records, receipts and proof downloads on the actual deployment.

The SQL revokes authenticated access to all 14 People RPCs, disables Employee-role app profiles, prevents new Employee-role assignments and restores manual ID entry. Existing Super Admin, Finance, Manager and Viewer profiles remain unchanged. No personnel, financial, audit, stored-file, Google-account or Supabase Auth records are deleted. Additional People tables, columns and the Employee enum value are preserved as inactive migration history. Do not rerun 006 or 007 after this rollback.

For a fresh finance-only database, apply 001 through 005 in order, then 008. Files 006 and 007 are retained solely as historical migrations for installations that already applied them.

## Verification

30 local tests pass, including rollback on a finance-only database, rollback after People migrations, repeated execution, record preservation, blocked retired RPCs and manual ID editing. Next.js route generation and TypeScript checks pass. These are local checks; Supabase configuration, Google credential revocation and Vercel deployment must be verified separately.

This is a feature rollback, not a claim that all original finance security findings were fixed. Manager/Viewer company-wide access and direct Finance reads without application view-audit events remain as in the original finance implementation.
