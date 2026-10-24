/// Curated vehicle makes/models for the vehicle form (Saudi market oriented).
///
/// Make values are the English name and are what gets stored and matched against
/// the module-address registry (shared/obd/modules.json), so keep them stable.
/// Models are a convenience list; any make/model not listed is still enterable
/// via the "Other" option (free text). Years are generated, not listed here.
library;

/// Make English name → Arabic display label.
const Map<String, String> kMakes = {
  'Toyota': 'تويوتا',
  'Lexus': 'لكزس',
  'Hyundai': 'هيونداي',
  'Kia': 'كيا',
  'Genesis': 'جينيسيس',
  'Nissan': 'نيسان',
  'Infiniti': 'إنفينيتي',
  'Honda': 'هوندا',
  'Mazda': 'مازدا',
  'Mitsubishi': 'ميتسوبيشي',
  'Suzuki': 'سوزوكي',
  'Isuzu': 'إيسوزو',
  'Ford': 'فورد',
  'Lincoln': 'لينكولن',
  'Chevrolet': 'شيفروليه',
  'GMC': 'جمس',
  'Cadillac': 'كاديلاك',
  'Dodge': 'دودج',
  'Jeep': 'جيب',
  'Chrysler': 'كرايسلر',
  'RAM': 'رام',
  'Mercedes-Benz': 'مرسيدس',
  'BMW': 'بي إم دبليو',
  'Audi': 'أودي',
  'Volkswagen': 'فولكسفاجن',
  'Land Rover': 'لاند روفر',
  'MG': 'إم جي',
  'Changan': 'شانجان',
  'Geely': 'جيلي',
  'Chery': 'شيري',
  'Hongqi': 'هونشي',
};

/// Make → common models (Latin). Empty/absent → the model field is free text.
const Map<String, List<String>> kModels = {
  'Toyota': ['Camry', 'Corolla', 'Land Cruiser', 'Prado', 'Hilux', 'RAV4', 'Yaris', 'Fortuner', 'Avalon', 'Rush', 'Innova', 'Hiace'],
  'Lexus': ['ES', 'LS', 'RX', 'NX', 'GX', 'LX', 'IS', 'UX'],
  'Hyundai': ['Accent', 'Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Creta', 'Azera', 'Palisade', 'Staria', 'Venue'],
  'Kia': ['Rio', 'Cerato', 'Optima', 'K5', 'Sportage', 'Sorento', 'Carnival', 'Seltos', 'Pegas', 'Telluride'],
  'Nissan': ['Sunny', 'Altima', 'Maxima', 'Patrol', 'X-Trail', 'Kicks', 'Pathfinder', 'Navara', 'Sentra'],
  'Honda': ['Accord', 'Civic', 'CR-V', 'Pilot', 'City', 'HR-V', 'Odyssey'],
  'Mazda': ['Mazda3', 'Mazda6', 'CX-3', 'CX-5', 'CX-9', 'CX-30', 'CX-60'],
  'Mitsubishi': ['Lancer', 'Attrage', 'Pajero', 'Montero Sport', 'L200', 'ASX', 'Xpander'],
  'Ford': ['Taurus', 'Focus', 'Fusion', 'Explorer', 'Expedition', 'Edge', 'F-150', 'Ranger', 'Territory', 'Mustang'],
  'Chevrolet': ['Malibu', 'Impala', 'Cruze', 'Captiva', 'Traverse', 'Tahoe', 'Suburban', 'Silverado', 'Camaro', 'Groove'],
  'GMC': ['Yukon', 'Sierra', 'Acadia', 'Terrain'],
  'Dodge': ['Charger', 'Challenger', 'Durango', 'Ram 1500'],
  'Jeep': ['Grand Cherokee', 'Wrangler', 'Cherokee', 'Compass', 'Gladiator'],
  'Chrysler': ['300', 'Pacifica'],
  'Mercedes-Benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'G-Class', 'A-Class', 'CLA'],
  'BMW': ['3 Series', '5 Series', '7 Series', 'X1', 'X3', 'X5', 'X6', 'X7'],
};

/// DB enum values for fuel type and transmission → (en, ar) labels.
const Map<String, (String, String)> kFuelTypes = {
  'gasoline': ('Gasoline', 'بنزين'),
  'diesel': ('Diesel', 'ديزل'),
  'hybrid': ('Hybrid', 'هايبرد'),
  'electric': ('Electric', 'كهربائي'),
  'flex': ('Flex', 'مرن'),
  'lpg': ('LPG', 'غاز مسال'),
  'cng': ('CNG', 'غاز طبيعي'),
  'other': ('Other', 'أخرى'),
};

const Map<String, (String, String)> kTransmissions = {
  'automatic': ('Automatic', 'أوتوماتيك'),
  'manual': ('Manual', 'عادي (مانيوال)'),
  'cvt': ('CVT', 'CVT'),
  'dct': ('DCT', 'DCT'),
  'other': ('Other', 'أخرى'),
};

List<String> modelsFor(String? make) => (make == null ? const <String>[] : (kModels[make] ?? const <String>[]));
