-- =============================================================================
-- AutoMind AI — reference data (migration 4/4)
-- Idempotent: safe to re-run.
-- =============================================================================

-- Standard OBD-II "pack": the public SAE J1979 / ISO 15031-5 services that any
-- compliant vehicle + ELM327 can provide. Manufacturer-specific packs are
-- separate rows with data_class = 'manufacturer_specific'.
insert into automind.manufacturer_packs
  (key, name, version, data_class, makes, year_from, year_to, supported_ecus, services,
   supported_devices, safety_requirements, license_source, status)
values (
  'sae_j1979_generic', 'Generic OBD-II (SAE J1979)', '1.0.0', 'standard_obd2', '{}', 1996, null,
  '[{"address": "7E0-7E7 / 7E8-7EF", "role": "emissions-related modules (OBD-II functional addressing)"}]',
  '["01 current data", "02 freeze frame", "03 stored DTCs", "04 clear DTCs", "07 pending DTCs", "09 vehicle info", "0A permanent DTCs"]',
  '[{"adapter_type": "elm327", "transports": ["wifi_tcp", "ble", "usb_serial"]}]',
  '{"note": "Read-only services plus service 04 (clear DTCs) behind explicit user consent, engine off."}',
  'SAE J1979 / ISO 15031-5 (public standard)', 'testing')
on conflict (key, version) do nothing;

-- Subscription plans. Prices are initial values for the Saudi market and are
-- meant to be edited from the admin dashboard; store product ids are filled
-- once the App Store / Google Play products exist.
insert into automind.subscription_plans
  (key, name_en, name_ar, audience, price_monthly, price_yearly, features, limits, sort_order)
values
  ('basic', 'Basic', 'الأساسية', 'individual', 0, 0,
   '{"read_dtcs": true, "basic_live_data": true, "short_report": true, "ai_analysis": false, "recordings": false, "replay": false, "maintenance_log": true, "alerts": false}',
   '{"vehicles": 1, "scans_per_month": 10, "live_signals": 4, "recording_retention_days": 0}', 1),
  ('pro', 'Pro', 'الاحترافية', 'individual', 29, 290,
   '{"read_dtcs": true, "basic_live_data": true, "short_report": true, "ai_analysis": true, "advanced_reports": true, "recordings": true, "replay": true, "maintenance_log": true, "alerts": true}',
   '{"vehicles": 3, "scans_per_month": 200, "live_signals": 12, "recording_retention_days": 365, "ai_requests_per_month": 100}', 2),
  ('garage_business', 'Garage Business', 'باقة الورش', 'business', 199, 1990,
   '{"read_dtcs": true, "basic_live_data": true, "short_report": true, "ai_analysis": true, "advanced_reports": true, "recordings": true, "replay": true, "maintenance_log": true, "alerts": true, "customer_vehicles": true, "technicians": true, "bookings": true, "quotes": true, "business_analytics": true}',
   '{"vehicles": 500, "scans_per_month": 3000, "technicians": 10, "live_signals": 24, "recording_retention_days": 730, "ai_requests_per_month": 2000}', 3)
on conflict (key) do nothing;

-- AutoMind Control procedures.
-- Level 1 (read / clear) is available; everything else is disabled until a
-- validated allow-list entry exists. Prohibited items can never be enabled.
insert into automind.service_procedures
  (key, level, name_en, name_ar, description_en, description_ar, risk_level, safety_category,
   required_engine_state, preconditions, obd_service, enabled_by_default, is_prohibited)
values
  ('read_live_data', 1, 'Read live data', 'قراءة البيانات الحية',
   'Read supported SAE J1979 service 01 parameters.', 'قراءة المعاملات القياسية المدعومة (الخدمة 01).',
   'low', 'general', 'any', '[]', '01', true, false),
  ('read_dtcs', 1, 'Read trouble codes', 'قراءة أكواد الأعطال',
   'Read stored (03), pending (07) and permanent (0A) DTCs.', 'قراءة الأكواد المخزنة والمعلقة والدائمة.',
   'low', 'general', 'ignition_on', '[]', '03', true, false),
  ('read_freeze_frame', 1, 'Read freeze frame', 'قراءة الإطار المجمد',
   'Read service 02 snapshot stored with a DTC.', 'قراءة لقطة البيانات المحفوظة مع كود العطل.',
   'low', 'general', 'ignition_on', '[]', '02', true, false),
  ('read_vehicle_info', 1, 'Read vehicle information', 'قراءة معلومات السيارة',
   'Read VIN and calibration IDs (service 09).', 'قراءة رقم الهيكل ومعرفات المعايرة (الخدمة 09).',
   'low', 'general', 'ignition_on', '[]', '09', true, false),
  ('clear_dtcs', 1, 'Clear trouble codes', 'مسح أكواد الأعطال',
   'Service 04: clears DTCs, freeze frames and resets readiness monitors. Requires engine off, ignition on, and explicit consent.',
   'الخدمة 04: تمسح الأكواد والإطار المجمد وتعيد ضبط مؤشرات الجاهزية. تتطلب إطفاء المحرك وتشغيل الإشعال وموافقة صريحة.',
   'medium', 'emissions', 'ignition_on',
   '["engine_off", "ignition_on", "user_consent", "vehicle_stationary"]', '04', true, false),
  ('reset_oil_service_indicator', 2, 'Reset oil service indicator', 'إعادة ضبط مؤشر صيانة الزيت',
   'Manufacturer-specific; requires a validated manufacturer pack and device.', 'خاصة بالشركة المصنعة؛ تتطلب حزمة وجهاز معتمدين.',
   'low', 'body', 'ignition_on', '["manufacturer_pack", "certified_device"]', null, false, false),
  ('battery_registration', 2, 'Battery registration', 'تسجيل البطارية',
   'Manufacturer-specific BMS registration after battery replacement.', 'تسجيل البطارية الجديدة في نظام إدارة البطارية.',
   'medium', 'powertrain', 'ignition_on', '["manufacturer_pack", "certified_device"]', null, false, false),
  ('throttle_body_relearn', 2, 'Throttle body relearn', 'إعادة تعلم بوابة الهواء',
   'Manufacturer-specific idle/throttle adaptation.', 'تهيئة بوابة الهواء الخاصة بالشركة المصنعة.',
   'medium', 'powertrain', 'running', '["manufacturer_pack", "certified_device", "engine_warm"]', null, false, false),
  ('evap_leak_test', 3, 'EVAP system leak test', 'اختبار تسريب نظام EVAP',
   'Service 08 on-board test; supported by few vehicles.', 'اختبار الخدمة 08؛ تدعمه سيارات قليلة.',
   'medium', 'emissions', 'running', '["manufacturer_pack", "certified_device", "vehicle_stationary"]', '08', false, false),
  ('ecu_adaptation', 4, 'ECU adaptation', 'تهيئة وحدة التحكم',
   'Future: OEM-licensed adaptation via certified hardware only.', 'مستقبلي: عبر أجهزة معتمدة وترخيص الشركة المصنعة فقط.',
   'high', 'powertrain', 'ignition_on', '["oem_license", "certified_device"]', null, false, false),
  ('ecu_coding', 4, 'ECU coding', 'برمجة وحدة التحكم',
   'Future: OEM-licensed coding via certified hardware only.', 'مستقبلي: عبر أجهزة معتمدة وترخيص الشركة المصنعة فقط.',
   'high', 'powertrain', 'ignition_on', '["oem_license", "certified_device"]', null, false, false),
  ('abs_bleed', 3, 'ABS hydraulic bleed', 'تنفيس منظومة ABS',
   'Safety-critical: brakes. Workshop + OEM-licensed only.', 'حرج للسلامة: الفرامل. للورش وبترخيص فقط.',
   'high', 'brakes', 'ignition_on', '["oem_license", "certified_device", "workshop_only"]', null, false, false),
  ('steering_angle_calibration', 3, 'Steering angle sensor calibration', 'معايرة حساس زاوية التوجيه',
   'Safety-critical: steering. Workshop + OEM-licensed only.', 'حرج للسلامة: التوجيه. للورش وبترخيص فقط.',
   'high', 'steering', 'running', '["oem_license", "certified_device", "workshop_only"]', null, false, false),
  -- Permanently prohibited
  ('odometer_adjustment', 4, 'Odometer adjustment', 'تعديل عداد المسافة',
   'Prohibited: illegal mileage manipulation.', 'محظور: التلاعب بعداد المسافة.',
   'prohibited', 'odometer', 'any', '[]', null, false, true),
  ('emissions_system_disable', 4, 'Disable emissions systems', 'تعطيل أنظمة الانبعاثات',
   'Prohibited: EGR/DPF/catalyst delete or monitor suppression.', 'محظور: إلغاء EGR/DPF/المحفز أو إخفاء المراقبات.',
   'prohibited', 'emissions', 'any', '[]', null, false, true),
  ('immobilizer_bypass', 4, 'Immobilizer bypass', 'تجاوز مانع التشغيل',
   'Prohibited: defeating vehicle anti-theft protection.', 'محظور: تجاوز حماية السيارة من السرقة.',
   'prohibited', 'immobilizer', 'any', '[]', null, false, true),
  ('airbag_crash_data_reset', 4, 'Airbag crash data reset', 'مسح بيانات تصادم الوسائد الهوائية',
   'Prohibited: SRS crash data must be handled by the manufacturer.', 'محظور: تُعالج بيانات التصادم لدى الشركة المصنعة.',
   'prohibited', 'airbag', 'any', '[]', null, false, true)
on conflict (key) do nothing;
