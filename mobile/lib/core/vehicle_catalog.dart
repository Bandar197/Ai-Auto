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
  'Hyundai': ['Accent', 'Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Creta', 'Azera', 'Palisade', 'Staria', 'Venue'],
  'Kia': ['Rio', 'Cerato', 'Optima', 'K5', 'Sportage', 'Sorento', 'Carnival', 'Seltos', 'Pegas', 'Telluride'],
  'Mitsubishi': ['Lancer', 'Attrage', 'Pajero', 'Montero Sport', 'L200', 'ASX', 'Xpander'],
  'Ford': ['Taurus', 'Focus', 'Fusion', 'Explorer', 'Expedition', 'Edge', 'F-150', 'Ranger', 'Territory', 'Mustang'],
  'Chevrolet': ['Malibu', 'Impala', 'Cruze', 'Captiva', 'Traverse', 'Tahoe', 'Suburban', 'Silverado', 'Camaro', 'Groove'],
  'Dodge': ['Charger', 'Challenger', 'Durango', 'Ram 1500'],
  'Jeep': ['Grand Cherokee', 'Wrangler', 'Cherokee', 'Compass', 'Gladiator'],
  'Chrysler': ['300', 'Pacifica'],
  'Mercedes-Benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'G-Class', 'A-Class', 'CLA'],
  'BMW': ['3 Series', '5 Series', '7 Series', 'X1', 'X3', 'X4', 'X5', 'X6', 'X7', 'i5', 'iX'],
  'Lexus': ['ES', 'LS', 'RX', 'NX', 'GX', 'LX', 'IS', 'UX', 'RC', 'LM'],
  'Genesis': ['G70', 'G80', 'G90', 'GV70', 'GV80'],
  'Infiniti': ['Q50', 'Q60', 'QX50', 'QX55', 'QX60', 'QX80'],
  'Suzuki': ['Swift', 'Baleno', 'Dzire', 'Vitara', 'Grand Vitara', 'Ciaz', 'Jimny', 'Ertiga', 'Fronx'],
  'Isuzu': ['D-Max', 'MU-X'],
  'Lincoln': ['Navigator', 'Aviator', 'Corsair', 'Nautilus'],
  'Cadillac': ['Escalade', 'XT4', 'XT5', 'XT6', 'CT4', 'CT5'],
  'RAM': ['1500', '2500', '3500'],
  'Audi': ['A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'e-tron'],
  'Volkswagen': ['Golf', 'Passat', 'Jetta', 'Tiguan', 'Teramont', 'Touareg', 'ID.4'],
  'Land Rover': ['Range Rover', 'Range Rover Sport', 'Range Rover Velar', 'Range Rover Evoque', 'Discovery', 'Discovery Sport', 'Defender'],
  'MG': ['MG5', 'MG6', 'ZS', 'HS', 'RX5', 'RX8', 'MG7', 'One'],
  'Changan': ['Alsvin', 'Eado', 'CS35 Plus', 'CS75 Plus', 'CS85', 'CS95', 'UNI-T', 'UNI-K'],
  'Geely': ['Emgrand', 'Coolray', 'Azkarra', 'Okavango', 'Tugella', 'Monjaro', 'Preface'],
  'Chery': ['Arrizo 5', 'Arrizo 6', 'Tiggo 4', 'Tiggo 7', 'Tiggo 8', 'Tiggo 8 Pro'],
  'Hongqi': ['H5', 'H9', 'HS5', 'HS7', 'E-HS9'],
  'GMC': ['Yukon', 'Yukon XL', 'Sierra', 'Acadia', 'Terrain', 'Canyon'],
  'Nissan': ['Sunny', 'Altima', 'Maxima', 'Patrol', 'X-Trail', 'Kicks', 'Pathfinder', 'Navara', 'Sentra', 'Armada', 'Patrol Nismo', 'Z'],
  'Honda': ['Accord', 'Civic', 'CR-V', 'Pilot', 'City', 'HR-V', 'Odyssey', 'ZR-V'],
  'Mazda': ['Mazda2', 'Mazda3', 'Mazda6', 'CX-3', 'CX-30', 'CX-5', 'CX-60', 'CX-9', 'CX-90', 'MX-5'],
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
