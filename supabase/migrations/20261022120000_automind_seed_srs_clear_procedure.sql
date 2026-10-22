-- =============================================================================
-- AutoMind AI — airbag (SRS) code clearing as a gated procedure (migration 5)
--
-- Clearing a *stored* SRS fault after a verified repair (e.g. a replaced clock
-- spring or a seat connector unplugged with the ignition on) is a normal
-- workshop step. It is NOT enabled by default: SRS access is manufacturer-
-- specific, so each make/model/adapter combination needs a validated
-- allow-list entry. The policy also refuses while any SRS fault is active
-- (clearing cannot fix it and would hide a real safety problem).
-- Crash/deployment data is never touched (airbag_crash_data_reset stays prohibited).
-- =============================================================================

insert into automind.service_procedures
  (key, level, name_en, name_ar, description_en, description_ar, risk_level, safety_category,
   required_engine_state, preconditions, obd_service, enabled_by_default, is_prohibited)
values
  ('clear_srs_dtcs', 2, 'Clear stored airbag (SRS) codes', 'مسح أكواد الوسائد الهوائية المخزنة',
   'Clears stored SRS fault memory after a verified repair. Refused while any SRS fault is active. Requires a validated manufacturer pack and certified adapter for the vehicle. Never clears crash/deployment data.',
   'يمسح ذاكرة أعطال الوسائد المخزنة بعد التأكد من الإصلاح. يُرفض إذا كان هناك عطل نشط. يتطلب حزمة شركة مصنعة معتمدة وجهازا معتمدا للسيارة. لا يمسح بيانات الحادث أبدا.',
   'medium', 'airbag', 'ignition_on',
   '["engine_off", "ignition_on", "no_active_srs_faults", "repair_confirmed", "manufacturer_pack", "certified_device", "user_consent"]',
   null, false, false)
on conflict (key) do nothing;
