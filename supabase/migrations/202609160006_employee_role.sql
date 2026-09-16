-- Apply and commit this migration before 007 (Postgres enum requirement).
alter type public.app_role add value if not exists 'employee';
