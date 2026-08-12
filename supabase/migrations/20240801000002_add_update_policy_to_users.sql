-- ============================================================================
-- DrsListing AI - Add UPDATE policy for users table
-- Date: 2024-08-01
-- Description: Allows anonymous users to update their own user row.
--   Required for updateUserRole() which sets the role and doctor_place_id
--   when a user connects as a doctor. Without this policy, the UPDATE
--   silently fails and the doctor_place_id is only saved locally.
-- ============================================================================

-- Allow anonymous users to update user rows (role, doctor_place_id)
CREATE POLICY "anon_can_update_users"
    ON public.users
    FOR UPDATE
    TO anon
    USING (true)
    WITH CHECK (true);
