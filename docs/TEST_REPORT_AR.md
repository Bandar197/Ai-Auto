# تقرير الاختبار — فاحص خارق (AutoMind)

**التاريخ:** 2026-10-25 · **الفرع:** `claude/automind-phase1`

**طريقة القراءة:**
- **PASS** = نجح في اختبار وحدة أو تكامل أو واجهة، على محاكي موسوم أو جهاز مُبرمَج في الاختبار.
- **NOT TESTED** = يحتاج سيارة حقيقية أو جهاز LONAUTO أو جهاز ويندوز حقيقي، ولم يُجرَّب بعد.
- **FAIL** = جُرّب وفشل.
- **غير منفّذ** = غير موجود في الكود.

> لا تُعدّ أي وظيفة «تعمل على سيارة» إلا بعد تجربة حقيقية. كل نتائج PASS أدناه من اختبارات آلية أو محاكاة.

**الأرقام الحالية:**
- التطبيق: 275 اختباراً ناجحاً (`flutter test`) والتحليل نظيف (`flutter analyze`).
- الخادم: 164 اختباراً ناجحاً و`ruff` نظيف. اختبارات الـ API التي تحتاج قاعدة بيانات (121) تُتخطّى محلياً وتعمل في CI.
- الويب: lint وtypecheck وvitest في CI.
- آخر CI أخضر قبل هذه الدفعة: `be96194`.

## الاتصال والجهاز
| الوظيفة | النتيجة | الدليل |
|---|---|---|
| طبقة ELM327 (أوامر AT، انتهاء المهلة، `?` = غير مدعوم) | PASS | `test/obd/elm327_test.dart` |
| اختبار قدرات الجهاز (الترويسات، الفلتر، ISO-TP، `?` ليس نجاحاً، إعادة الحالة) | PASS | `capability_probe_test.dart`, `adapter_screen_test.dart` |
| اتصال LONAUTO حقيقي عبر BLE / COM | **NOT TESTED** | يحتاج الجهاز |
| BLE مع تحديد MTU/تقسيم صريح | غير منفّذ | — |
| اكتشاف محاكي الكمبيوتر (يُعرض دائماً تجريبي) | PASS | `simulator_detection_test.dart` |

## القراءة والفحص
| الوظيفة | النتيجة | الدليل |
|---|---|---|
| الخدمات 01/02/03/07/09/0A وفكّ الـ PIDs | PASS | `pid_decoder_test.dart`, `obd_client_demo_test.dart`, `frame_parser_test.dart` |
| الخدمة 06 (نجاح/فشل من القيم الخام، القيم الموقّعة، CAN فقط) | PASS | `monitor_tests_test.dart` |
| UDS 0x19 + NRC + «انتظر» 0x78 + إعادة تجميع الإطارات المتعددة | PASS | `uds_test.dart`, `uds_pending_test.dart`, `uds_scan_outcome_test.dart` |
| حالات الوحدة العشر وخريطة الوحدات | PASS | `ecu_map_test.dart` |
| الاكتشاف من العناوين المعتمدة فقط (لا مسح أعمى) | PASS | `module_registry_test.dart`, `test_uds_scan_profiles.py` |
| الماركة من رقم الهيكل + أوصاف الأكواد حسب الماركة | PASS | `kb_make_aware_test.dart`, `test_kb_make_aware.py` |
| فحص سريع/كامل على المحاكي (تجريبي) | PASS | `scan_flow_test.dart`, `full_scan_recording_test.dart` |
| قراءة الإيرباق في سوناتا 2012 (استجابة موثقة أو «لا استجابة» مع السبب) | **NOT TESTED** | يحتاج السيارة؛ المنطق مختبر |
| جلسات UDS (0x10) وKWP2000 | غير منفّذ | — |

## مسح الأعطال
| الوظيفة | النتيجة | الدليل |
|---|---|---|
| المخطط بالسياقات الثمانية والقائمتين | PASS | `clear_planner_test.dart`, `clear_screen_test.dart` |
| لقطة دائمة قبل أي أمر + سجل تدقيق كامل | PASS | `clear_offline_audit_test.dart` |
| مسح المحرك 04 بدون اتصال، بموافقة وسجل محلي | PASS | `clear_offline_audit_test.dart` |
| مسح 04 بموافقة الخادم ثم إعادة الفحص والحكم | PASS | `clear_verify_flow_test.dart` |
| بوابة UDS 0x14 (رفض قبل الإرسال؛ 0x54/NRC؛ إعادة القراءة تحسم) | PASS | `clear_offline_audit_test.dart` |
| الأكواد الدائمة بعد 04 تُعرض «التحقق معلّق» | PASS | `clear_offline_audit_test.dart` |
| «تم مسح الكود» منفصل عن «انطفأت اللمبة» | PASS | `clear_offline_audit_test.dart` |
| مسح على سيارة حقيقية | **NOT TESTED** | — |

## السجل والتصدير
| الوظيفة | النتيجة | الدليل |
|---|---|---|
| سجل كامل للأوامر والردود + إخفاء رقم الهيكل عند المشاركة | PASS | `traffic_test.dart` |
| سجل لا يضيع + استعادة الجلسة المنقطعة | PASS | `session_journal_test.dart` |
| CSV عربي (UTF-8 BOM)، JSON v2، حزمة ZIP مع SHA-256 | PASS | `export_service_test.dart`, `test_recording_v2_schema.py` |
| Excel متعدد الأوراق (فُتح بقارئ مستقل openpyxl) | PASS | `xlsx_export_test.dart` |
| PDF عربي/إنجليزي على الجهاز (مُعاين بصرياً) | PASS | `report_pdf_test.dart` |
| استيراد جلسة / رفض الحزمة المعدّلة / مقارنة جلستين | PASS | `session_import_compare_test.dart`, `compare_screen_test.dart` |
| البحث والفلاتر ومجلد الجلسات (مسار ويندوز) | PASS | `history_folder_test.dart` |
| فتح المجلد في ويندوز فعلياً | **NOT TESTED** | يحتاج ويندوز |
| فحص المساحة الحرّة قبل الحفظ | غير منفّذ | — |
| SQLite بنمط WAL | غير منفّذ (البديل: ملفات JSON إضافية فقط مع كتابة ذرية) | — |

## الواجهة والسلامة
| الوظيفة | النتيجة | الدليل |
|---|---|---|
| لمبات الطبلون (لا «سليم» بدون قراءة) | PASS | `indicators_test.dart`, `indicators_screen_test.dart` |
| تشخيص المطوّر (أوامر القراءة فقط) | PASS | `dev_console_policy_test.dart`, `dev_console_test.dart` |
| العربية من اليمين لليسار | PASS | `home_rtl_test.dart` |
| التجريبي لا يتحول إلى حقيقي أبداً | PASS | `recorder_replay_test.dart`, `session_import_compare_test.dart` |
| عزل بيانات كل مستخدم (الخادم) | PASS في CI | `test_tenant_isolation.py` |

## حالات الأعطال (القسم 11-H)
| الحالة | النتيجة |
|---|---|
| NO DATA / انتهاء المهلة / إطارات ناقصة / عنوان CAN خاطئ | PASS (اختبارات ELM/UDS) |
| JSON تالف عند الاستيراد | PASS (`session_import_compare_test.dart`) |
| تعطّل التطبيق وسط الفحص | PASS بالمحاكاة (`session_journal_test.dart`) · **NOT TESTED** على جهاز |
| BLE غير مدعوم / منفذ COM مشغول / رفض الصلاحية / البطارية ضعيفة / القرص ممتلئ | **NOT TESTED** |

## الأداء والبناء
| البند | النتيجة |
|---|---|
| بناء ويندوز وأندرويد وiOS | PASS في CI (ملفات البناء متاحة في GitHub Actions) |
| التشغيل على ويندوز 10/11 + الأداء والذاكرة | **NOT TESTED** |

## ما يلزم للانتقال من NOT TESTED إلى PASS
جلسة واحدة على سوناتا 2012 مع جهاز LONAUTO:
1. افتح «قدرات جهاز الفحص» ثم شغّل الفحص الكامل.
2. احفظ مجلد الجلسة.
3. أرسل حزمة الأدلة ZIP.

هذا يكفي لتأكيد البروتوكول والقدرات، وهل تستجيب وحدة الإيرباق، ثم تحديث `modules.json` وملف السيارة.
