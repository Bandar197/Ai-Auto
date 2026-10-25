/// Curated, honest car-diagnostics knowledge shown in the in-app guide. Content is
/// bilingual (ar/en) and intentionally general — it explains what things mean and what
/// to do, and never promises a fix or tells the driver to disable a safety system.
library;

class KnowledgeItem {
  const KnowledgeItem({required this.titleEn, required this.titleAr, required this.bodyEn, required this.bodyAr, this.icon});
  final String titleEn;
  final String titleAr;
  final String bodyEn;
  final String bodyAr;
  final String? icon; // optional material icon name handled by the screen
  String title(String lang) => lang == 'ar' ? titleAr : titleEn;
  String body(String lang) => lang == 'ar' ? bodyAr : bodyEn;
}

class KnowledgeSection {
  const KnowledgeSection({required this.titleEn, required this.titleAr, required this.items});
  final String titleEn;
  final String titleAr;
  final List<KnowledgeItem> items;
  String title(String lang) => lang == 'ar' ? titleAr : titleEn;
}

/// Warning lights — what each commonly means and what a driver should do.
const _warningLights = KnowledgeSection(
  titleEn: 'Dashboard warning lights',
  titleAr: 'لمبات التحذير في اللوحة',
  items: [
    KnowledgeItem(
      icon: 'engine',
      titleEn: 'Check engine (MIL)',
      titleAr: 'لمبة فحص المحرك',
      bodyEn: 'The engine/emissions system stored a fault. Steady light: have it scanned soon. Flashing: a misfire that can damage the catalytic converter — reduce load and get it checked now.',
      bodyAr: 'النظام سجّل عطلاً في المحرك أو الانبعاثات. ثابتة: افحصها قريباً. وامضة: احتراق غير منتظم قد يتلف الحساس الحفّاز — خفّف الحمل وافحصها فوراً.',
    ),
    KnowledgeItem(
      icon: 'airbag',
      titleEn: 'Airbag (SRS)',
      titleAr: 'لمبة الوسائد الهوائية (SRS)',
      bodyEn: 'The restraint system has a fault and the airbags may NOT deploy in a crash. This is a safety system — have a specialist read it with the correct equipment. Do not ignore it, and never disconnect the module yourself.',
      bodyAr: 'نظام تقييد الحركة به عطل وقد لا تنفخ الوسائد عند الحادث. هذا نظام سلامة — راجع متخصصاً لقراءته بالجهاز الصحيح. لا تتجاهلها ولا تفصل الوحدة بنفسك.',
    ),
    KnowledgeItem(
      icon: 'abs',
      titleEn: 'ABS',
      titleAr: 'لمبة نظام ABS',
      bodyEn: 'Anti-lock braking has a fault. Normal braking usually still works, but anti-lock may be disabled. Get it checked — leave regular stopping distance meanwhile.',
      bodyAr: 'نظام منع انغلاق الفرامل به عطل. الفرملة العادية غالباً تعمل، لكن قد يتعطّل منع الانغلاق. افحصها، واترك مسافة توقف كافية حتى ذلك.',
    ),
    KnowledgeItem(
      icon: 'oil',
      titleEn: 'Oil pressure',
      titleAr: 'ضغط الزيت',
      bodyEn: 'Low oil pressure can destroy the engine in minutes. If it comes on while driving, stop safely and switch off; check the oil level before restarting.',
      bodyAr: 'انخفاض ضغط الزيت قد يُتلف المحرك خلال دقائق. إذا أضاءت أثناء القيادة، توقّف بأمان وأطفئ المحرك، وافحص مستوى الزيت قبل التشغيل.',
    ),
    KnowledgeItem(
      icon: 'battery',
      titleEn: 'Battery / charging',
      titleAr: 'البطارية / الشحن',
      bodyEn: 'The charging system may not be keeping the battery charged (often the alternator or belt). The car may stall once the battery drains — get it checked soon.',
      bodyAr: 'قد لا يشحن النظام البطارية بشكل كافٍ (غالباً الدينامو أو السير). قد تتوقف السيارة عند فراغ البطارية — افحصها قريباً.',
    ),
    KnowledgeItem(
      icon: 'temp',
      titleEn: 'Coolant temperature',
      titleAr: 'حرارة سائل التبريد',
      bodyEn: 'The engine is overheating. Stop safely and let it cool — never open the radiator cap while hot. Driving on can warp the head.',
      bodyAr: 'المحرك يسخن زيادة. توقّف بأمان ودعه يبرد — لا تفتح غطاء الرديتر وهو ساخن. الاستمرار قد يُعوّج رأس المحرك.',
    ),
  ],
);

/// What each system category means in a scan.
const _systems = KnowledgeSection(
  titleEn: 'Vehicle systems',
  titleAr: 'أنظمة السيارة',
  items: [
    KnowledgeItem(
      titleEn: 'Engine & emissions',
      titleAr: 'المحرك والانبعاثات',
      bodyEn: 'Read over standard OBD-II on every car. Covers fuel, ignition, air intake, sensors and the emissions monitors behind the check-engine light.',
      bodyAr: 'تُقرأ عبر OBD-II القياسي في كل سيارة. تشمل الوقود والإشعال وسحب الهواء والحساسات ومراقبات الانبعاثات خلف لمبة فحص المحرك.',
    ),
    KnowledgeItem(
      titleEn: 'Transmission',
      titleAr: 'ناقل الحركة',
      bodyEn: 'Gearbox control. Many transmission faults appear as standard codes; some need the maker-specific module.',
      bodyAr: 'التحكم في القير. كثير من أعطال ناقل الحركة تظهر كأكواد قياسية، وبعضها يحتاج وحدة الشركة المصنّعة.',
    ),
    KnowledgeItem(
      titleEn: 'Airbag (SRS), ABS & body',
      titleAr: 'الوسائد (SRS) وABS والهيكل',
      bodyEn: 'Not on standard OBD — each is read from its own module at a per-car address. If the address is unknown or a security gateway blocks it, the app says "couldn\'t verify" instead of pretending the system is healthy.',
      bodyAr: 'ليست على OBD القياسي — تُقرأ كلٌّ من وحدتها بعنوان خاص لكل سيارة. إن كان العنوان مجهولاً أو منعته بوابة أمنية، يقول التطبيق «تعذّر التحقق» بدل ادّعاء أن النظام سليم.',
    ),
  ],
);

/// General maintenance tips.
const _tips = KnowledgeSection(
  titleEn: 'Maintenance tips',
  titleAr: 'نصائح الصيانة',
  items: [
    KnowledgeItem(
      titleEn: 'Clearing a code is not a repair',
      titleAr: 'مسح الكود ليس إصلاحاً',
      bodyEn: 'Erasing a fault code turns the light off but does not fix the cause. If the fault is real, the code comes back — fix the root cause first.',
      bodyAr: 'مسح كود العطل يُطفئ اللمبة لكنه لا يُصلح السبب. إن كان العطل فعلياً فسيعود الكود — عالج السبب أولاً.',
    ),
    KnowledgeItem(
      titleEn: 'Keep up with oil & filters',
      titleAr: 'التزم بالزيت والفلاتر',
      bodyEn: 'Change oil and the oil/air filters on the maker\'s schedule. Clean oil and air are the cheapest protection for the engine.',
      bodyAr: 'غيّر الزيت وفلاتر الزيت والهواء حسب جدول الشركة. الزيت والهواء النظيفان أرخص حماية للمحرك.',
    ),
    KnowledgeItem(
      titleEn: 'Check tyres & pressure',
      titleAr: 'افحص الإطارات والضغط',
      bodyEn: 'Correct tyre pressure improves safety, fuel economy and tyre life — check monthly and before long trips, especially in hot weather.',
      bodyAr: 'الضغط الصحيح للإطارات يحسّن السلامة والاقتصاد وعمر الإطار — افحصه شهرياً وقبل الرحلات الطويلة، خاصة في الحر.',
    ),
    KnowledgeItem(
      titleEn: 'Don\'t ignore safety lights',
      titleAr: 'لا تتجاهل لمبات السلامة',
      bodyEn: 'Airbag, ABS and brake warnings affect how the car protects you in an emergency. Have them checked promptly by a qualified workshop.',
      bodyAr: 'تحذيرات الوسائد وABS والفرامل تؤثر في حماية السيارة لك وقت الطوارئ. افحصها سريعاً لدى ورشة مؤهلة.',
    ),
  ],
);

const List<KnowledgeSection> kKnowledge = [_warningLights, _systems, _tips];
