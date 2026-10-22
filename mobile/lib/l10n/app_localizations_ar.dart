// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'أوتومايند';

  @override
  String get ok => 'حسنًا';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get close => 'إغلاق';

  @override
  String get next => 'التالي';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String errorGeneric(Object error) {
    return 'حدث خطأ: $error';
  }

  @override
  String get unknown => 'غير معروف';

  @override
  String get done => 'تم';

  @override
  String get share => 'مشاركة';

  @override
  String get exportJson => 'تصدير JSON';

  @override
  String get exportCsv => 'تصدير CSV';

  @override
  String get notAvailable => 'غير متوفر';

  @override
  String get modeLive => 'مباشر';

  @override
  String get modeDemo => 'تجريبي';

  @override
  String get modeReplay => 'إعادة تشغيل';

  @override
  String get demoBanner => 'تجريبي — بيانات محاكاة وليست من سيارة حقيقية';

  @override
  String replayBanner(Object mode) {
    return 'إعادة تشغيل لتسجيل $mode';
  }

  @override
  String get simulatorLabel => 'محاكي';

  @override
  String get demoWatermark => 'تجريبي';

  @override
  String get replayWatermark => 'إعادة';

  @override
  String get onboardingTitle1 => 'افهم سيارتك';

  @override
  String get onboardingBody1 =>
      'وصّل قارئ OBD-II من نوع ELM327 بسيارتك واقرأ أكواد الأعطال الحقيقية وبيانات الحساسات مباشرة.';

  @override
  String get onboardingTitle2 => 'أدلة لا تخمينات';

  @override
  String get onboardingBody2 =>
      'كل نتيجة توضّح ما تم قياسه وما تم استنتاجه، مع فحوصات للتأكد قبل شراء أي قطعة.';

  @override
  String get onboardingTitle3 => 'يعمل بدون إنترنت';

  @override
  String get onboardingBody3 =>
      'قد تقطع قارئات Wi-Fi اتصال الإنترنت. تُحفظ الفحوصات على الجوال وتُرفع لاحقًا.';

  @override
  String get getStarted => 'ابدأ';

  @override
  String get continueOffline => 'المتابعة بدون حساب';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get register => 'إنشاء حساب';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get password => 'كلمة المرور';

  @override
  String get fullName => 'الاسم الكامل';

  @override
  String acceptTerms(Object version) {
    return 'أوافق على شروط الخدمة (الإصدار $version)';
  }

  @override
  String acceptPrivacy(Object version) {
    return 'أوافق على سياسة الخصوصية (الإصدار $version) ومعالجة بيانات سيارتي';
  }

  @override
  String get consentRequired => 'الموافقتان مطلوبتان لإنشاء الحساب.';

  @override
  String get passwordPolicy =>
      '10 أحرف على الأقل، ومختلفة عن بريدك الإلكتروني.';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get noAccount => 'ليس لديك حساب؟ أنشئ حسابًا';

  @override
  String get haveAccount => 'لديك حساب؟ سجّل الدخول';

  @override
  String get mfaCode => 'رمز المصادقة';

  @override
  String get invalidEmail => 'أدخل بريدًا إلكترونيًا صحيحًا';

  @override
  String get homeTitle => 'الرئيسية';

  @override
  String get vehicleNone => 'لم يتم اختيار سيارة';

  @override
  String get addVehicle => 'إضافة سيارة';

  @override
  String get adapterLabel => 'القارئ';

  @override
  String get ecuLabel => 'السيارة (ECU)';

  @override
  String get healthScore => 'صحة السيارة';

  @override
  String get healthUnknown => 'لا يوجد تشخيص بعد';

  @override
  String get healthBand_good => 'جيدة';

  @override
  String get healthBand_fair => 'مقبولة';

  @override
  String get healthBand_attention => 'تحتاج انتباه';

  @override
  String get healthBand_critical => 'حرجة';

  @override
  String dtcCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count كود عطل',
      many: '$count كود عطل',
      few: '$count أكواد أعطال',
      two: 'كودا عطل',
      one: 'كود عطل واحد',
      zero: 'لا توجد أكواد أعطال',
    );
    return '$_temp0';
  }

  @override
  String get importantAlerts => 'تنبيهات مهمة';

  @override
  String get noAlerts => 'لا توجد تنبيهات مهمة';

  @override
  String lastScan(Object when) {
    return 'آخر فحص: $when';
  }

  @override
  String get never => 'لا يوجد';

  @override
  String get startScan => 'ابدأ الفحص';

  @override
  String get liveData => 'البيانات المباشرة';

  @override
  String get maintenanceHistory => 'سجل الصيانة';

  @override
  String get sessionsHistory => 'سجل الفحوصات';

  @override
  String get connect => 'اتصال';

  @override
  String pendingUploads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count فحص بانتظار الرفع',
      few: '$count فحوصات بانتظار الرفع',
      two: 'فحصان بانتظار الرفع',
      one: 'فحص واحد بانتظار الرفع',
    );
    return '$_temp0';
  }

  @override
  String get uploadNow => 'ارفع الآن';

  @override
  String get adapterDisconnected => 'غير متصل';

  @override
  String get adapterConnecting => 'جارٍ الاتصال…';

  @override
  String get adapterConnected => 'متصل';

  @override
  String get adapterError => 'خطأ';

  @override
  String get ecuUnknown => 'لم يُفحص';

  @override
  String get ecuSearching => 'جارٍ البحث…';

  @override
  String get ecuConnected => 'يستجيب';

  @override
  String get ecuNoResponse => 'لا يستجيب';

  @override
  String get ecuBusError => 'خطأ في الناقل';

  @override
  String get linkIdle => 'اختر طريقة الاتصال.';

  @override
  String get linkConnectingAdapter => 'الجوال ← القارئ: جارٍ الاتصال…';

  @override
  String get linkAdapterUnreachable =>
      'لا يستطيع الجوال الوصول إلى القارئ. تأكد من الاتصال بشبكة Wi-Fi الخاصة بالقارئ (أو تشغيل البلوتوث) ومن عنوان IP والمنفذ.';

  @override
  String get linkAdapterTimeout =>
      'لم يرد القارئ في الوقت المحدد (الاتصال بين الجوال والقارئ).';

  @override
  String get linkAdapterNotElm =>
      'الجهاز استجاب لكنه ليس قارئًا متوافقًا مع ELM327.';

  @override
  String get linkInitializing => 'تم العثور على القارئ، جارٍ التهيئة…';

  @override
  String get linkSearchingProtocol =>
      'القارئ ← السيارة: جارٍ البحث عن بروتوكول OBD (يجب تشغيل مفتاح الإشعال)…';

  @override
  String get linkEcuConnected => 'القارئ والسيارة متصلان.';

  @override
  String get linkEcuNoResponse =>
      'القارئ يعمل لكن السيارة لم تستجب. شغّل مفتاح الإشعال (أو المحرك) وتأكد من تثبيت القارئ جيدًا.';

  @override
  String get linkEcuBusError =>
      'يبلغ القارئ عن خطأ في ناقل السيارة. جرّب بروتوكولًا آخر أو افحص التوصيلات.';

  @override
  String get linkLost => 'انقطع الاتصال بالقارئ.';

  @override
  String get linkReconnecting => 'جارٍ إعادة الاتصال…';

  @override
  String get linkReconnected => 'تمت إعادة الاتصال.';

  @override
  String get linkDisconnected => 'تم قطع الاتصال.';

  @override
  String get connectTitle => 'الاتصال';

  @override
  String get transportWifi => 'Wi-Fi';

  @override
  String get transportBle => 'بلوتوث LE';

  @override
  String get wifiHost => 'عنوان IP للقارئ';

  @override
  String get wifiPort => 'المنفذ';

  @override
  String get protocol => 'البروتوكول';

  @override
  String get protocolAuto => 'تلقائي';

  @override
  String get bleScan => 'ابحث عن القارئات';

  @override
  String get bleScanning => 'جارٍ البحث…';

  @override
  String get bleNoDevices => 'لم يتم العثور على قارئات بلوتوث بعد.';

  @override
  String get bleNote =>
      'قارئات البلوتوث LE تظهر بالبحث — لا حاجة للإقران من إعدادات النظام.';

  @override
  String get transportClassic => 'بلوتوث كلاسيكي';

  @override
  String get transportSerial => 'منفذ COM (بلوتوث كلاسيكي أو USB)';

  @override
  String get classicIosNote =>
      'لا يسمح الآيفون باستخدام قارئات البلوتوث الكلاسيكي (SPP) في التطبيقات العادية (تشترط Apple ملحقات MFi). استخدم قارئ بلوتوث LE أو Wi-Fi.';

  @override
  String get classicAndroidNote =>
      'اقرن القارئ أولًا من إعدادات أندرويد ← البلوتوث (الرمز غالبًا 1234 أو 0000)، ثم اختره هنا.';

  @override
  String get classicDesktopNote =>
      'ويندوز: اقرن القارئ من الإعدادات ← Bluetooth والأجهزة (الرمز غالبًا 1234 أو 0000). ينشئ ويندوز منفذ COM صادر — اختره هنا. قارئات USB تظهر أيضًا كمنافذ COM.';

  @override
  String get classicNoDevices =>
      'لم يتم العثور على قارئات مقترنة أو منافذ COM.';

  @override
  String get classicBluetoothOff => 'البلوتوث مطفأ أو غير متوفر.';

  @override
  String get baudRate => 'سرعة المنفذ (Baud)';

  @override
  String get refresh => 'تحديث';

  @override
  String get lastUsed => 'آخر استخدام';

  @override
  String get wifiInternetNote =>
      'عند اتصال الجوال بشبكة Wi-Fi الخاصة بالقارئ قد ينقطع الإنترنت. يُحفظ الفحص على الجوال ويُرفع تلقائيًا لاحقًا.';

  @override
  String get demoScenarios => 'سيناريوهات تجريبية';

  @override
  String get demoExplain =>
      'الوضع التجريبي يستخدم محاكيًا مدمجًا، وتُعلَّم النتائج بوضوح بأنها تجريبية.';

  @override
  String get replayFromFile => 'فتح ملف تسجيل';

  @override
  String get replayFromServer => 'التسجيلات على الخادم';

  @override
  String get replayLocal => 'التسجيلات على هذا الجوال';

  @override
  String get noRecordings => 'لا توجد تسجيلات بعد.';

  @override
  String get connectButton => 'اتصل';

  @override
  String get disconnect => 'قطع الاتصال';

  @override
  String get simulateEngineOff => 'محاكاة إيقاف المحرك';

  @override
  String get scanTitle => 'الفحص';

  @override
  String get stepAdapter => 'الاتصال بالقارئ';

  @override
  String get stepInit => 'تهيئة القارئ';

  @override
  String get stepProtocol => 'تحديد البروتوكول';

  @override
  String get stepEcu => 'العثور على وحدات التحكم';

  @override
  String get stepSupported => 'قراءة الحساسات المدعومة';

  @override
  String get stepVin => 'قراءة رقم الهيكل';

  @override
  String get stepDtcs => 'قراءة أكواد الأعطال (03/07/0A)';

  @override
  String get stepFreeze => 'قراءة الإطار المجمد';

  @override
  String get stepCapture => 'التقاط البيانات المباشرة';

  @override
  String get stepUpload => 'الرفع والتشخيص';

  @override
  String captureProgress(int seconds) {
    return 'متبقٍ $seconds ث';
  }

  @override
  String get viewReport => 'عرض التقرير';

  @override
  String scanFailed(Object reason) {
    return 'توقف الفحص: $reason';
  }

  @override
  String get cancelScan => 'إيقاف';

  @override
  String get scanSkipped => 'تم التخطي';

  @override
  String get scanQueued => 'تم الحفظ — سيُرفع عند توفر الإنترنت';

  @override
  String get reportTitle => 'تقرير التشخيص';

  @override
  String get summary => 'الملخص';

  @override
  String get technicianSummary => 'للفني';

  @override
  String get dtcsTitle => 'أكواد الأعطال';

  @override
  String get noDtcs => 'لا توجد أكواد أعطال.';

  @override
  String get findings => 'النتائج';

  @override
  String get severity_low => 'منخفضة';

  @override
  String get severity_medium => 'متوسطة';

  @override
  String get severity_high => 'عالية';

  @override
  String get severity_critical => 'حرجة';

  @override
  String get severity_info => 'معلومة';

  @override
  String confidence(int value) {
    return 'الثقة $value٪';
  }

  @override
  String get probableCauses => 'الأسباب المحتملة';

  @override
  String likelihood(int value) {
    return '$value٪';
  }

  @override
  String get evidence => 'الأدلة';

  @override
  String get measured => 'مُقاس';

  @override
  String get inferred => 'مُستنتج';

  @override
  String get observed => 'المرصود';

  @override
  String get expected => 'المتوقع';

  @override
  String get tests => 'الفحوصات المقترحة';

  @override
  String get actions => 'الإجراءات';

  @override
  String get partsToConfirm => 'قطع (تأكد أولًا)';

  @override
  String get requiresConfirmation => 'يتطلب التأكيد';

  @override
  String get missingData => 'بيانات غير متوفرة';

  @override
  String get disclaimers => 'إخلاء المسؤولية';

  @override
  String get systemStatus => 'الأنظمة';

  @override
  String get dataQuality => 'جودة البيانات';

  @override
  String get offlineReportNote =>
      'بدون إنترنت: تُعرض معاني أكواد الأعطال من قاعدة المعرفة المدمجة فقط. التحليل الكامل يحتاج الخادم، وهذا الفحص في قائمة الرفع.';

  @override
  String get kbUnknownCode => 'الوصف غير موجود في قاعدة المعرفة.';

  @override
  String get analyzeNow => 'حلّل على الخادم';

  @override
  String get freezeFrame => 'الإطار المجمد';

  @override
  String get vinLabel => 'رقم الهيكل';

  @override
  String get howTo => 'الطريقة';

  @override
  String get expectedResult => 'النتيجة المتوقعة';

  @override
  String get liveTitle => 'البيانات المباشرة';

  @override
  String get chooseSignals => 'الإشارات';

  @override
  String get record => 'تسجيل';

  @override
  String get stopRecording => 'إيقاف';

  @override
  String get recordingSaved => 'تم حفظ التسجيل';

  @override
  String get compareWith => 'مقارنة مع تسجيل';

  @override
  String get clearCompare => 'إزالة المقارنة';

  @override
  String sampleRate(Object rate) {
    return '$rate عينة/ث';
  }

  @override
  String get outOfRange => 'خارج النطاق';

  @override
  String get noSupportedSignals => 'لم تُبلغ السيارة عن إشارات مدعومة.';

  @override
  String get notConnected => 'غير متصل. اتصل أولًا.';

  @override
  String get historyTitle => 'سجل الفحوصات';

  @override
  String get noSessions => 'لا توجد فحوصات بعد.';

  @override
  String get localOnly => 'على الجوال فقط';

  @override
  String get synced => 'مرفوع';

  @override
  String get vehiclesTitle => 'السيارات';

  @override
  String get make => 'الشركة المصنعة';

  @override
  String get model => 'الطراز';

  @override
  String get year => 'سنة الصنع';

  @override
  String get plate => 'اللوحة';

  @override
  String get nickname => 'اسم مختصر';

  @override
  String get odometer => 'عداد المسافة (كم)';

  @override
  String get fuelTypeLabel => 'نوع الوقود';

  @override
  String get engineLabel => 'المحرك';

  @override
  String get transmission => 'ناقل الحركة';

  @override
  String get selectVehicle => 'استخدم هذه السيارة';

  @override
  String get maintenanceTitle => 'سجل الصيانة';

  @override
  String get addRecord => 'إضافة سجل';

  @override
  String get serviceType => 'نوع الخدمة';

  @override
  String get date => 'التاريخ';

  @override
  String get notes => 'ملاحظات';

  @override
  String get cost => 'التكلفة (ريال)';

  @override
  String get noMaintenance => 'لا توجد سجلات صيانة.';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get language => 'اللغة';

  @override
  String get arabic => 'العربية';

  @override
  String get english => 'English';

  @override
  String get backendUrl => 'عنوان الخادم';

  @override
  String get adapterSettings => 'القارئ';

  @override
  String get commandTimeout => 'مهلة الأمر (مللي ثانية)';

  @override
  String get searchTimeout => 'مهلة البحث عن البروتوكول (مللي ثانية)';

  @override
  String get bleUuidOverride => 'تخصيص معرفات BLE (الخدمة / الإشعار / الكتابة)';

  @override
  String get includeVin => 'تضمين رقم الهيكل عند الرفع';

  @override
  String get captureDuration => 'مدة الالتقاط أثناء الفحص (ث)';

  @override
  String get account => 'الحساب';

  @override
  String get notLoggedIn => 'لم يتم تسجيل الدخول';

  @override
  String get clearDtcsTitle => 'مسح أكواد الأعطال';

  @override
  String get clearDtcsWarning =>
      'مسح الأكواد يطفئ لمبة فحص المحرك لكنه لا يصلح العطل. ستُعاد ضبط جميع مراقبات الجاهزية، وقد لا تجتاز السيارة الفحص الدوري حتى تكمل دورة قيادة كاملة، وستُحذف بيانات الإطار المجمد. ستعود الأكواد إذا كان العطل ما زال موجودًا.';

  @override
  String get clearDtcsChecklist =>
      'المحرك مطفأ، مفتاح الإشعال يعمل، السيارة متوقفة.';

  @override
  String get clearDtcsConfirm => 'أفهم ذلك — امسح الأكواد';

  @override
  String get clearRequiresServer =>
      'مسح الأكواد يحتاج موافقة الخادم. اتصل بالإنترنت وسجّل الدخول.';

  @override
  String clearConditionsFailed(Object reason) {
    return 'تم الرفض: $reason';
  }

  @override
  String get clearSuccess => 'تم مسح أكواد الأعطال.';

  @override
  String get clearFailed => 'لم تؤكد السيارة طلب المسح.';

  @override
  String clearRejected(Object reason) {
    return 'رفض الخادم الطلب: $reason';
  }

  @override
  String get clearDemoNote =>
      'وضع تجريبي/محاكي: لا يصل أي أمر إلى سيارة حقيقية.';

  @override
  String get selectAll => 'الكل';

  @override
  String get seconds => 'ث';

  @override
  String get verifyTitle => 'تحقق بعد المسح';

  @override
  String get verifyOverall_problem_confirmed => 'يوجد عطل حقيقي';

  @override
  String get verifyOverall_likely_resolved => 'غالبا عطل قديم';

  @override
  String get verifyOverall_verifying => 'التحقق مستمر';

  @override
  String get verifyOverall_nothing_cleared => 'لا يوجد ما يتم التحقق منه';

  @override
  String verifyChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count فحص بعد المسح',
      few: '$count فحوصات بعد المسح',
      two: 'فحصان بعد المسح',
      one: 'فحص واحد بعد المسح',
      zero: 'لا يوجد فحص بعد المسح',
    );
    return '$_temp0';
  }

  @override
  String get verifyCheckNow => 'افحص الآن';

  @override
  String get verifyRunScan => 'فحص كامل';

  @override
  String get verifyClose => 'إنهاء التحقق';

  @override
  String verifyClearedAt(Object when) {
    return 'تم المسح: $when';
  }

  @override
  String get verifySourceServer => 'النتيجة من خادم أوتومايند';

  @override
  String get verifySourceLocal =>
      'نتيجة بدون إنترنت محسوبة على الجوال (بنفس قواعد الخادم)';

  @override
  String get verifyNextStep => 'الخطوة التالية';

  @override
  String get verifyBeforeCodes => 'المحفوظ قبل المسح';

  @override
  String get verifyHomeCard => 'المسح والتحقق';

  @override
  String get verifyNone => 'لا يوجد مسح للتحقق منه بعد.';

  @override
  String get verifyHowItWorks =>
      'إذا رجع الكود بعد المسح فهناك عطل حقيقي. وإذا لم يرجع بعد أن تعيد السيارة اختباراتها الذاتية فغالبا كان عطلا قديما.';

  @override
  String checkLabel(int n) {
    return 'الفحص رقم $n';
  }

  @override
  String get noCodesInCheck => 'لا توجد أكواد';

  @override
  String get viewVerification => 'عرض التحقق';

  @override
  String get clearErases => 'سيؤدي المسح إلى حذف';

  @override
  String get clearErasesFreeze =>
      'الإطار المجمد (ظروف حدوث العطل). تبقى نسخة منه في الفحص المحفوظ.';

  @override
  String get clearErasesReadiness => 'جميع مراقبات الجاهزية تبدأ من الصفر:';

  @override
  String get clearScanSaved =>
      'الفحص (الأكواد والإطار المجمد) محفوظ على الخادم.';

  @override
  String get clearScanNotSaved =>
      'سيتم حفظ الفحص على الخادم أولًا — لا يُسمح بالمسح إلا بعد حفظ الأكواد.';

  @override
  String get clearNoReport => 'قم بالفحص أولًا: يجب حفظ الأكواد قبل المسح.';

  @override
  String get clearPhase_checking => 'التحقق من إطفاء المحرك وتوقف السيارة…';

  @override
  String get clearPhase_uploading => 'حفظ الفحص على الخادم…';

  @override
  String get clearPhase_requesting => 'طلب موافقة الخادم…';

  @override
  String get clearPhase_clearing => 'جارٍ مسح الأكواد…';

  @override
  String get clearPhase_waiting => 'انتظار بضع ثوانٍ…';

  @override
  String get clearPhase_rechecking => 'إعادة فحص الأكواد…';

  @override
  String get clearFailReplay => 'غير متاح في إعادة التشغيل.';

  @override
  String get clearFailUnreadable =>
      'لا يمكن قراءة سرعة المحرك أو سرعة السيارة، لذلك المسح غير آمن.';

  @override
  String clearFailEngine(Object rpm) {
    return 'المحرك يعمل ($rpm دورة/د). أطفئ المحرك واترك الإشعال يعمل.';
  }

  @override
  String clearFailMoving(Object speed) {
    return 'السيارة تتحرك ($speed كم/س).';
  }

  @override
  String clearFailUpload(Object reason) {
    return 'تعذر حفظ الفحص على الخادم: $reason';
  }

  @override
  String get otherProcedures => 'إجراءات أخرى';

  @override
  String get procedureUnavailable => 'غير متاح';

  @override
  String get srsNote =>
      'لا يقوم التطبيق أبدًا بمسح أكواد الوسائد الهوائية (SRS).';

  @override
  String get autoStartAfterClear => 'تجريبي: تشغيل المحرك تلقائيًا بعد المسح';

  @override
  String get monitorComplete => 'مكتمل';

  @override
  String get monitorIncomplete => 'غير مكتمل';
}
