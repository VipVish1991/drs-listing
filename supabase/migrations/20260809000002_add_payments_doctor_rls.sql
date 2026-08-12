-- ============================================================================
-- 8b. PAYMENTS — DOCTOR-SIDE RLS (clinics mark offline payments Paid/Refunded)
-- ============================================================================
-- The payments table is patient-scoped (x-user-id = patient_id). This
-- migration adds the doctor half: a clinic — a `doctors` row whose `user_id`
-- is the caller's x-user-id header — may READ payment rows for its own
-- appointments and flip their status (offline 'Pending' → 'Paid' /
-- 'Refunded') from the doctor appointments screen.
--
-- Ownership is proven the same way every other payment/notification policy
-- works: the caller's UUID travels in the `x-user-id` request header and is
-- matched against `doctors.user_id` (a TEXT UUID, stored by the app's
-- saveDoctorToDb) and then against `payments.doctor_place_id`. A caller with
-- no owned clinics (or no header) matches nothing — fails closed, with no
-- UUID cast so a malformed header cannot error out.
--
-- UPDATE is column-restricted to payment_status / paid_at / updated_at, so a
-- clinic can never rewrite the amount, patient, method, or doctor_place_id.

-- ── 1. Doctors may READ payment rows for clinics they own ──────────────
DROP POLICY IF EXISTS "payments_select_doctor" ON public.payments;
CREATE POLICY "payments_select_doctor" ON public.payments
    FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.user_id = (current_setting('request.headers', true)::jsonb ->> 'x-user-id')
              AND d.place_id = payments.doctor_place_id
        )
    );

-- ── 2. Doctors may UPDATE the status of payment rows for their clinics ──
DROP POLICY IF EXISTS "payments_update_doctor" ON public.payments;
CREATE POLICY "payments_update_doctor" ON public.payments
    FOR UPDATE
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.user_id = (current_setting('request.headers', true)::jsonb ->> 'x-user-id')
              AND d.place_id = payments.doctor_place_id
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.user_id = (current_setting('request.headers', true)::jsonb ->> 'x-user-id')
              AND d.place_id = payments.doctor_place_id
        )
    );

-- ── 3. Column-restrict the UPDATE surface ───────────────────────────────
-- After this, an UPDATE can only touch payment_status / paid_at /
-- updated_at — the clinic's status flips and nothing else.
REVOKE UPDATE ON public.payments FROM anon, authenticated;
GRANT UPDATE (payment_status, paid_at, updated_at)
    ON public.payments TO anon, authenticated;

COMMENT ON POLICY "payments_select_doctor" ON public.payments IS
    'A clinic (doctors row owned by the x-user-id caller) can read payment rows for its own appointments — powers the payment line on the doctor appointments screen.';
COMMENT ON POLICY "payments_update_doctor" ON public.payments IS
    'A clinic can flip the status of payment rows for its own appointments (offline Pending -> Paid / Refunded). UPDATE is column-restricted to payment_status / paid_at / updated_at.';
