/// Service 01 PID 01 (monitor status since DTCs cleared) → readiness map.
/// Same shape as backend `automind.obd.pids.decode_monitor_status`:
/// `{mil_on, dtc_count, ignition, monitors: {name: {available, complete}}}`.
library;

const List<String> _sparkMonitors = ['misfire', 'fuel_system', 'components'];
const List<String> _sparkExtended = [
  'catalyst', 'heated_catalyst', 'evap_system', 'secondary_air', 'ac_refrigerant', 'o2_sensor', 'o2_sensor_heater', 'egr_system',
];
const List<String?> _dieselExtended = [
  'nmhc_catalyst', 'nox_scr', null, 'boost_pressure', null, 'exhaust_gas_sensor', 'pm_filter', 'egr_vvt',
];

/// [data] = the 4 bytes A B C D after `41 01`.
Map<String, dynamic>? decodeMonitorStatus(List<int> data) {
  if (data.length < 4) return null;
  final a = data[0], b = data[1], c = data[2], d = data[3];
  final compression = b & 0x08 != 0;
  final monitors = <String, Map<String, bool>>{};
  for (var i = 0; i < _sparkMonitors.length; i++) {
    if (b & (1 << i) != 0) monitors[_sparkMonitors[i]] = {'available': true, 'complete': b & (1 << (i + 4)) == 0};
  }
  final names = compression ? _dieselExtended : _sparkExtended;
  for (var i = 0; i < names.length; i++) {
    final n = names[i];
    if (n != null && c & (1 << i) != 0) monitors[n] = {'available': true, 'complete': d & (1 << i) == 0};
  }
  return {
    'mil_on': a & 0x80 != 0,
    'dtc_count': a & 0x7F,
    'ignition': compression ? 'compression' : 'spark',
    'monitors': monitors,
  };
}

/// Names of available monitors that have not completed.
List<String> incompleteMonitors(Map<String, dynamic>? readiness) {
  final m = readiness?['monitors'];
  if (m is! Map) return const [];
  return [
    for (final e in m.entries)
      if (e.value is Map && e.value['available'] != false && e.value['complete'] == false) '${e.key}',
  ];
}
