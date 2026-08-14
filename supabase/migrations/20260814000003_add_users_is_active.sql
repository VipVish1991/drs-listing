-- Add an Active/Inactive switch to user accounts.
--
-- `is_active` defaults to TRUE so every existing account stays usable
-- after this migration. An admin flips it to FALSE to block the account:
-- the app refuses login / warm-start session restore and shows
-- "Your account is inactive. Please contact our support team."

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN public.users.is_active IS
    'Account status: TRUE = active (can log in), FALSE = inactive (login blocked, user told to contact support). Defaults to TRUE.';
