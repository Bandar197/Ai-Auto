/// Vehicle systems used to stage a full scan and group fault codes by category
/// (engine, emissions, transmission, electrical, airbag, ABS, body, network).
library;

import 'package:flutter/material.dart';

import '../obd/obd.dart';

/// Where a stage's codes come from.
enum ScanSource { obd, modules }

class VehicleSystem {
  const VehicleSystem(this.id, this.nameEn, this.nameAr, this.icon, this.source);
  final String id;
  final String nameEn;
  final String nameAr;
  final IconData icon;
  final ScanSource source;

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
}

/// Ordered catalogue of systems. OBD systems come from the standard scan (services
/// 03/07/0A across every responding ECU); module systems come from per-module UDS reads.
const List<VehicleSystem> kVehicleSystems = [
  VehicleSystem('engine', 'Engine', 'المحرك', Icons.settings_suggest, ScanSource.obd),
  VehicleSystem('emissions', 'Emissions', 'الانبعاثات', Icons.cloud_outlined, ScanSource.obd),
  VehicleSystem('transmission', 'Transmission', 'ناقل الحركة (القير)', Icons.swap_calls, ScanSource.obd),
  VehicleSystem('electrical', 'Electrical / Charging', 'الكهرباء / الشحن', Icons.bolt, ScanSource.obd),
  VehicleSystem('airbag', 'Airbag (SRS)', 'الوسائد الهوائية (SRS)', Icons.airline_seat_legroom_extra, ScanSource.modules),
  VehicleSystem('abs', 'ABS / Brakes', 'ABS / الفرامل', Icons.disc_full, ScanSource.modules),
  VehicleSystem('body', 'Body', 'الهيكل', Icons.directions_car_filled, ScanSource.modules),
  VehicleSystem('network', 'Network', 'شبكة الاتصال', Icons.hub, ScanSource.obd),
];

final Map<String, VehicleSystem> _byId = {for (final s in kVehicleSystems) s.id: s};

VehicleSystem systemById(String id) => _byId[id] ?? kVehicleSystems.first;

const Set<String> _emissionsSub = {'emissions', 'evap', 'exhaust'};
const Set<String> _electricalSub = {'charging', 'electrical'};

/// Which system a trouble code belongs to, using its letter and (when known) the
/// knowledge-base subsystem. Powertrain (P) codes split into engine / emissions /
/// transmission / electrical; C→ABS, B→airbag or body, U→network.
String systemIdForDtc(String code, {String? subsystem}) {
  if (code.isEmpty) return 'engine';
  switch (code[0].toUpperCase()) {
    case 'C':
      return 'abs';
    case 'U':
      return 'network';
    case 'B':
      return subsystem == 'airbag' ? 'airbag' : 'body';
    case 'P':
    default:
      if (subsystem == 'transmission') return 'transmission';
      if (subsystem != null && _emissionsSub.contains(subsystem)) return 'emissions';
      if (subsystem != null && _electricalSub.contains(subsystem)) return 'electrical';
      return 'engine';
  }
}

/// System for a UDS module result (airbag/abs/other → body).
String systemIdForModuleCategory(ModuleCategory c) => switch (c) {
      ModuleCategory.airbag => 'airbag',
      ModuleCategory.abs => 'abs',
      ModuleCategory.other => 'body',
    };
