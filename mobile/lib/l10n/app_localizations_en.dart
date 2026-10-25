// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Super Scanner';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get deleteScanTitle => 'Delete this scan?';

  @override
  String get deleteScanBody =>
      'This removes the saved scan and its recording from this phone. Reports already uploaded stay on the server.';

  @override
  String get deleteScanDone => 'Scan deleted.';

  @override
  String get knowledgeTitle => 'Guide & tips';

  @override
  String get knowledgeSubtitle =>
      'What the warning lights mean, how each system is read, and practical maintenance tips.';

  @override
  String get reportModulesTitle => 'Module scan (airbag / ABS / body)';

  @override
  String get moduleReadCodes => 'Stored codes';

  @override
  String get moduleNoCodes => 'Read — no stored codes';

  @override
  String get moduleRefused => 'Present but refused the read (security gateway)';

  @override
  String get moduleNoResponse => 'No response — couldn\'t verify';

  @override
  String get moduleAirbagUnverified =>
      'Couldn\'t verify the airbag (SRS). If the light is on it may be a real fault — see a specialist.';

  @override
  String get edit => 'Edit';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String get next => 'Next';

  @override
  String get loading => 'Loading…';

  @override
  String errorGeneric(Object error) {
    return 'Something went wrong: $error';
  }

  @override
  String get unknown => 'Unknown';

  @override
  String get done => 'Done';

  @override
  String get share => 'Share';

  @override
  String get exportJson => 'Export JSON';

  @override
  String get exportEvidence => 'Export evidence bundle (ZIP)';

  @override
  String get exportEvidenceNoRecording =>
      'No local recording for this scan — the evidence bundle needs the saved session.';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get notAvailable => 'Not available';

  @override
  String get modeLive => 'Live';

  @override
  String get modeDemo => 'Demo';

  @override
  String get modeReplay => 'Replay';

  @override
  String get demoBanner => 'DEMO — simulated data, not from a real vehicle';

  @override
  String replayBanner(Object mode) {
    return 'REPLAY of a $mode recording';
  }

  @override
  String get simulatorLabel => 'Simulator';

  @override
  String get demoWatermark => 'DEMO';

  @override
  String get replayWatermark => 'REPLAY';

  @override
  String get onboardingTitle1 => 'Understand your car';

  @override
  String get onboardingBody1 =>
      'Plug an ELM327 OBD-II adapter into your car and read real fault codes and live sensor data.';

  @override
  String get onboardingTitle2 => 'Evidence, not guesses';

  @override
  String get onboardingBody2 =>
      'Every finding shows what was measured and what was inferred, with tests to confirm before buying parts.';

  @override
  String get onboardingTitle3 => 'Works offline';

  @override
  String get onboardingBody3 =>
      'Wi-Fi adapters may cut your internet. Scans are saved on the phone and uploaded later.';

  @override
  String get getStarted => 'Get started';

  @override
  String get continueOffline => 'Continue without an account';

  @override
  String get login => 'Log in';

  @override
  String get register => 'Create account';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get fullName => 'Full name';

  @override
  String acceptTerms(Object version) {
    return 'I accept the Terms of Service (v$version)';
  }

  @override
  String acceptPrivacy(Object version) {
    return 'I accept the Privacy Policy (v$version) and the processing of my vehicle data';
  }

  @override
  String get consentRequired =>
      'Both consents are required to create an account.';

  @override
  String get passwordPolicy =>
      'At least 10 characters, different from your email.';

  @override
  String get logout => 'Log out';

  @override
  String get noAccount => 'No account? Create one';

  @override
  String get haveAccount => 'Already registered? Log in';

  @override
  String get mfaCode => 'Authenticator code';

  @override
  String get invalidEmail => 'Enter a valid email';

  @override
  String get homeTitle => 'Home';

  @override
  String get vehicleNone => 'No vehicle selected';

  @override
  String get addVehicle => 'Add vehicle';

  @override
  String get adapterLabel => 'Adapter';

  @override
  String get ecuLabel => 'Car (ECU)';

  @override
  String get healthScore => 'Vehicle health';

  @override
  String get healthUnknown => 'No diagnosis yet';

  @override
  String get healthBand_good => 'Good';

  @override
  String get healthBand_fair => 'Fair';

  @override
  String get healthBand_attention => 'Needs attention';

  @override
  String get healthBand_critical => 'Critical';

  @override
  String dtcCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fault codes',
      one: '1 fault code',
      zero: 'No fault codes',
    );
    return '$_temp0';
  }

  @override
  String get importantAlerts => 'Important alerts';

  @override
  String get noAlerts => 'No important alerts';

  @override
  String lastScan(Object when) {
    return 'Last scan: $when';
  }

  @override
  String get never => 'never';

  @override
  String get startScan => 'Start scan';

  @override
  String get liveData => 'Live data';

  @override
  String get maintenanceHistory => 'Maintenance';

  @override
  String get sessionsHistory => 'Scan history';

  @override
  String get connect => 'Connect';

  @override
  String pendingUploads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scans waiting to upload',
      one: '1 scan waiting to upload',
    );
    return '$_temp0';
  }

  @override
  String get uploadNow => 'Upload now';

  @override
  String get adapterDisconnected => 'Not connected';

  @override
  String get adapterConnecting => 'Connecting…';

  @override
  String get adapterConnected => 'Connected';

  @override
  String get adapterError => 'Error';

  @override
  String get ecuUnknown => 'Not checked';

  @override
  String get ecuSearching => 'Searching…';

  @override
  String get ecuConnected => 'Responding';

  @override
  String get ecuNoResponse => 'No response';

  @override
  String get ecuBusError => 'Bus error';

  @override
  String get linkIdle => 'Choose how to connect.';

  @override
  String get linkConnectingAdapter => 'Phone → adapter: connecting…';

  @override
  String get linkAdapterUnreachable =>
      'The phone cannot reach the adapter. Check that you joined the adapter\'s Wi-Fi (or Bluetooth is on) and the IP/port.';

  @override
  String get linkAdapterTimeout =>
      'The adapter did not answer in time (phone → adapter link).';

  @override
  String get linkAdapterNotElm =>
      'The device answered but is not an ELM327-compatible adapter.';

  @override
  String get linkInitializing => 'Adapter found, initialising…';

  @override
  String get linkSearchingProtocol =>
      'Adapter → car: searching for the OBD protocol (ignition must be ON)…';

  @override
  String get linkEcuConnected => 'Adapter and car are talking.';

  @override
  String get linkEcuNoResponse =>
      'The adapter works but the car did not answer. Turn the ignition ON (or start the engine) and check the adapter is fully seated.';

  @override
  String get linkEcuBusError =>
      'The adapter reports a bus error on the car side. Try another protocol or check wiring.';

  @override
  String get linkLost => 'Connection to the adapter was lost.';

  @override
  String get linkReconnecting => 'Reconnecting…';

  @override
  String get linkReconnected => 'Reconnected.';

  @override
  String get linkDisconnected => 'Disconnected.';

  @override
  String get connectTitle => 'Connect';

  @override
  String get transportWifi => 'Wi-Fi';

  @override
  String get transportBle => 'Bluetooth LE';

  @override
  String get wifiHost => 'Adapter IP';

  @override
  String get wifiPort => 'Port';

  @override
  String get protocol => 'Protocol';

  @override
  String get protocolAuto => 'Automatic';

  @override
  String get bleScan => 'Scan for adapters';

  @override
  String get bleScanning => 'Scanning…';

  @override
  String get bleNoDevices => 'No Bluetooth adapters found yet.';

  @override
  String get bleNote =>
      'Bluetooth LE adapters are found by scanning — no pairing in system settings needed.';

  @override
  String get transportClassic => 'Bluetooth Classic';

  @override
  String get transportSerial => 'Serial / COM (Bluetooth Classic or USB)';

  @override
  String get classicIosNote =>
      'iPhone does not allow Bluetooth Classic (SPP) OBD adapters in normal apps (Apple requires MFi accessories). Use a Bluetooth LE or Wi-Fi adapter.';

  @override
  String get classicAndroidNote =>
      'Pair the adapter first in Android Settings → Bluetooth (PIN usually 1234 or 0000), then choose it here.';

  @override
  String get classicDesktopNote =>
      'Windows: pair the adapter in Settings → Bluetooth & devices (PIN usually 1234 or 0000). Windows then creates an outgoing COM port — choose it here. USB adapters also appear as COM ports.';

  @override
  String get classicNoDevices => 'No paired adapters / COM ports found.';

  @override
  String get classicBluetoothOff => 'Bluetooth is off or not available.';

  @override
  String get baudRate => 'Baud rate';

  @override
  String get refresh => 'Refresh';

  @override
  String get lastUsed => 'Last used';

  @override
  String get wifiInternetNote =>
      'When the phone joins the adapter\'s Wi-Fi it may lose internet. The scan is saved on the phone and uploaded automatically later.';

  @override
  String get demoScenarios => 'Demo scenarios';

  @override
  String get demoExplain =>
      'Demo uses a built-in simulator. Results are clearly labelled DEMO.';

  @override
  String get replayFromFile => 'Open recording file';

  @override
  String get replayFromServer => 'Recordings on the server';

  @override
  String get replayLocal => 'Recordings on this phone';

  @override
  String get noRecordings => 'No recordings yet.';

  @override
  String get connectButton => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get simulateEngineOff => 'Simulate engine off';

  @override
  String get scanTitle => 'Scan';

  @override
  String get stepAdapter => 'Connect to adapter';

  @override
  String get stepInit => 'Initialise adapter';

  @override
  String get stepProtocol => 'Detect protocol';

  @override
  String get stepEcu => 'Find control units';

  @override
  String get stepSupported => 'Read supported sensors';

  @override
  String get stepVin => 'Read VIN';

  @override
  String get stepDtcs => 'Read fault codes (03/07/0A)';

  @override
  String get stepFreeze => 'Read freeze frame';

  @override
  String get stepCapture => 'Capture live data';

  @override
  String get stepUpload => 'Upload & diagnose';

  @override
  String captureProgress(int seconds) {
    return '$seconds s left';
  }

  @override
  String get viewReport => 'View report';

  @override
  String scanFailed(Object reason) {
    return 'Scan stopped: $reason';
  }

  @override
  String get cancelScan => 'Stop';

  @override
  String get scanSkipped => 'Skipped';

  @override
  String get scanQueued => 'Saved — will upload when online';

  @override
  String get reportTitle => 'Diagnosis report';

  @override
  String get summary => 'Summary';

  @override
  String get technicianSummary => 'For the technician';

  @override
  String get dtcsTitle => 'Fault codes';

  @override
  String get noDtcs => 'No fault codes reported.';

  @override
  String get findings => 'Findings';

  @override
  String get severity_low => 'Low';

  @override
  String get severity_medium => 'Medium';

  @override
  String get severity_high => 'High';

  @override
  String get severity_critical => 'Critical';

  @override
  String get severity_info => 'Info';

  @override
  String confidence(int value) {
    return 'Confidence $value%';
  }

  @override
  String get probableCauses => 'Probable causes';

  @override
  String likelihood(int value) {
    return '$value%';
  }

  @override
  String get evidence => 'Evidence';

  @override
  String get measured => 'Measured';

  @override
  String get inferred => 'Inferred';

  @override
  String get observed => 'Observed';

  @override
  String get expected => 'Expected';

  @override
  String get tests => 'Recommended tests';

  @override
  String get actions => 'Actions';

  @override
  String get partsToConfirm => 'Parts (confirm first)';

  @override
  String get requiresConfirmation => 'Requires confirmation';

  @override
  String get missingData => 'Missing data';

  @override
  String get disclaimers => 'Disclaimers';

  @override
  String get systemStatus => 'Systems';

  @override
  String get dataQuality => 'Data quality';

  @override
  String get offlineReportNote =>
      'Offline: showing fault-code meanings from the built-in knowledge base only. Full analysis needs the server; this scan is queued for upload.';

  @override
  String get kbUnknownCode => 'Description not in the knowledge base.';

  @override
  String get analyzeNow => 'Analyse on server';

  @override
  String get freezeFrame => 'Freeze frame';

  @override
  String get vinLabel => 'VIN';

  @override
  String get howTo => 'How';

  @override
  String get expectedResult => 'Expected result';

  @override
  String get liveTitle => 'Live data';

  @override
  String get chooseSignals => 'Signals';

  @override
  String get record => 'Record';

  @override
  String get stopRecording => 'Stop';

  @override
  String get recordingSaved => 'Recording saved';

  @override
  String get compareWith => 'Compare with recording';

  @override
  String get clearCompare => 'Remove comparison';

  @override
  String sampleRate(Object rate) {
    return '$rate samples/s';
  }

  @override
  String get outOfRange => 'Out of range';

  @override
  String get noSupportedSignals => 'No supported signals reported by the car.';

  @override
  String get notConnected => 'Not connected. Connect first.';

  @override
  String get historyTitle => 'Scan history';

  @override
  String get noSessions => 'No scans yet.';

  @override
  String get localOnly => 'On phone only';

  @override
  String get synced => 'Uploaded';

  @override
  String get vehiclesTitle => 'Vehicles';

  @override
  String get make => 'Make';

  @override
  String get model => 'Model';

  @override
  String get year => 'Year';

  @override
  String get plate => 'Plate';

  @override
  String get nickname => 'Nickname';

  @override
  String get odometer => 'Odometer (km)';

  @override
  String get fuelTypeLabel => 'Fuel type';

  @override
  String get engineLabel => 'Engine';

  @override
  String get transmission => 'Transmission';

  @override
  String get selectVehicle => 'Use this vehicle';

  @override
  String get maintenanceTitle => 'Maintenance log';

  @override
  String get addRecord => 'Add record';

  @override
  String get serviceType => 'Service';

  @override
  String get date => 'Date';

  @override
  String get notes => 'Notes';

  @override
  String get cost => 'Cost (SAR)';

  @override
  String get noMaintenance => 'No maintenance records.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get arabic => 'العربية';

  @override
  String get english => 'English';

  @override
  String get backendUrl => 'Backend URL';

  @override
  String get adapterSettings => 'Adapter';

  @override
  String get commandTimeout => 'Command timeout (ms)';

  @override
  String get searchTimeout => 'Protocol search timeout (ms)';

  @override
  String get bleUuidOverride => 'BLE UUID override (service / notify / write)';

  @override
  String get includeVin => 'Include VIN in uploads';

  @override
  String get captureDuration => 'Live capture during scan (s)';

  @override
  String get account => 'Account';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String get clearDtcsTitle => 'Clear fault codes';

  @override
  String get clearDtcsWarning =>
      'Clearing codes turns off the check-engine light but does NOT fix the fault. All readiness monitors reset, so the car may fail an inspection until it completes a full drive cycle, and freeze-frame data is erased. Codes will return if the fault is still present.';

  @override
  String get clearDtcsChecklist => 'Engine OFF, ignition ON, vehicle stopped.';

  @override
  String get clearDtcsConfirm => 'I understand — clear codes';

  @override
  String clearCodesCount(int count) {
    return 'Clear $count code(s)';
  }

  @override
  String get clearWillReturnNote =>
      'Clearing turns the light off but does not fix the fault — codes return if the problem is real.';

  @override
  String get extendedModulesTitle => 'Airbag / ABS modules';

  @override
  String get extendedModulesIntro =>
      'Reads fault codes from modules a normal scan does not reach — airbag (SRS), ABS and body control — over manufacturer diagnostics. Read-only.';

  @override
  String get extendedScanCta => 'Scan airbag / ABS modules';

  @override
  String get extendedNeedsLive =>
      'Available in live mode only (needs a real car).';

  @override
  String get extendedNoModules =>
      'No module answered. The addresses may need tuning for this car, or a security gateway is blocking access.';

  @override
  String get extendedRefused =>
      'Present, but it refused the request (may be gateway-protected).';

  @override
  String get extendedNoFaults => 'No faults';

  @override
  String get extendedDisclaimer =>
      'Module addresses are discovery starting points, confirmed per vehicle. Codes read here are over manufacturer diagnostics and should be verified on the car.';

  @override
  String get extendedAirbagClearNote =>
      'Clearing airbag codes is a separate, gated step: it is refused while a fault is active, and only after the repair is confirmed.';

  @override
  String get explainTitle => 'Explain code';

  @override
  String get explainCta => 'Explain this code';

  @override
  String get explainByAi => 'AI explanation, grounded in the knowledge base.';

  @override
  String get explainFromKb => 'From the knowledge base.';

  @override
  String get explainOffline =>
      'Offline: shown from the built-in knowledge base.';

  @override
  String get whatToCheck => 'What to check first';

  @override
  String get explainVideos => 'Videos';

  @override
  String get linkOpenFailed => 'Could not open the link.';

  @override
  String get otherOption => 'Other…';

  @override
  String get controllersCatalogTitle => 'Controller catalogue';

  @override
  String get controllersCatalogNote =>
      'Reference list of control-module names per manufacturer. These are UNVERIFIED catalogue entries — not CAN addresses and not proof a module is readable on your car. Readable modules come from an actual scan.';

  @override
  String get unverifiedCatalogEntry => 'Unverified catalog entry';

  @override
  String get allMakes => 'All makes';

  @override
  String get search => 'Search';

  @override
  String get deepScanCta => 'Deep module discovery';

  @override
  String get deepScanNote =>
      'Probes every common address to find modules not yet mapped for your car (e.g. the airbag unit). Slower but thorough. If a module with a fault shows up, send us its address so we can lock it in.';

  @override
  String get fullScanFindMore =>
      'Expected a fault (e.g. airbag) that didn\'t show? Try deep discovery.';

  @override
  String get systemUnverified =>
      'Couldn\'t verify this system — its module did not respond. Not read as healthy.';

  @override
  String get airbagUnverified =>
      'Couldn\'t verify the airbag (SRS) system — specialist diagnosis needed. If the airbag light is on, it may be a real fault.';

  @override
  String get fullScanTitle => 'Full scan by system';

  @override
  String get fullScanCta => 'Start full scan';

  @override
  String get fullScanChecking => 'Scanning…';

  @override
  String get fullScanAllClear => 'No fault codes found in the systems scanned.';

  @override
  String fullScanSummary(int count) {
    return '$count fault code(s) found';
  }

  @override
  String fullScanUnverifiedNote(int count) {
    return 'Couldn\'t verify $count system(s) — not shown as healthy.';
  }

  @override
  String get fullScanCoverageNote =>
      'Engine, emissions, transmission, electrical and network come from the standard scan. Airbag, ABS and body are read per module and depend on your car\'s addresses being supported; a security gateway can block some modules.';

  @override
  String get fullScanSaveReport => 'Save & view report';

  @override
  String get clearRequiresServer =>
      'Clearing codes needs server approval. Connect to the internet and log in.';

  @override
  String clearConditionsFailed(Object reason) {
    return 'Refused: $reason';
  }

  @override
  String get clearSuccess => 'Fault codes cleared.';

  @override
  String get clearFailed => 'The car did not confirm the clear request.';

  @override
  String clearRejected(Object reason) {
    return 'The server rejected the request: $reason';
  }

  @override
  String get clearDemoNote =>
      'Demo/simulator: no command reaches a real vehicle.';

  @override
  String get selectAll => 'All';

  @override
  String get seconds => 's';

  @override
  String get verifyTitle => 'Verify after clear';

  @override
  String get verifyOverall_problem_confirmed => 'Real problem';

  @override
  String get verifyOverall_likely_resolved => 'Most likely an old fault';

  @override
  String get verifyOverall_verifying => 'Verification in progress';

  @override
  String get verifyOverall_nothing_cleared => 'Nothing to verify';

  @override
  String verifyChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count checks since clearing',
      one: '1 check since clearing',
      zero: 'No check since clearing yet',
    );
    return '$_temp0';
  }

  @override
  String get verifyCheckNow => 'Check now';

  @override
  String get verifyRunScan => 'Full scan';

  @override
  String get verifyClose => 'End verification';

  @override
  String verifyClearedAt(Object when) {
    return 'Cleared: $when';
  }

  @override
  String get verifySourceServer => 'Verdict from the AutoMind server';

  @override
  String get verifySourceLocal =>
      'Offline verdict calculated on the phone (same rules as the server)';

  @override
  String get verifyNextStep => 'Next step';

  @override
  String get verifyBeforeCodes => 'Saved before clearing';

  @override
  String get verifyHomeCard => 'Clear & verify';

  @override
  String get verifyNone => 'No clear to verify yet.';

  @override
  String get verifyHowItWorks =>
      'If a cleared code comes back, you have a real problem. If it stays away after the car re-runs its self-tests, it was most likely an old fault.';

  @override
  String checkLabel(int n) {
    return 'Check #$n';
  }

  @override
  String get noCodesInCheck => 'No codes';

  @override
  String get viewVerification => 'View verification';

  @override
  String get clearErases => 'Clearing will erase';

  @override
  String get clearErasesFreeze =>
      'The freeze frame (conditions when the fault happened). A copy stays in the saved scan.';

  @override
  String get clearErasesReadiness =>
      'All readiness monitors restart from zero:';

  @override
  String get clearScanSaved =>
      'The scan (codes + freeze frame) is saved on the server.';

  @override
  String get clearScanNotSaved =>
      'The scan will be saved on the server first — clearing is only allowed after the codes are saved.';

  @override
  String get clearNoReport =>
      'Run a scan first: the codes must be saved before clearing.';

  @override
  String get clearPhase_checking => 'Checking engine off and speed 0…';

  @override
  String get clearPhase_uploading => 'Saving the scan on the server…';

  @override
  String get clearPhase_requesting => 'Requesting server approval…';

  @override
  String get clearPhase_clearing => 'Clearing codes…';

  @override
  String get clearPhase_waiting => 'Waiting a few seconds…';

  @override
  String get clearPhase_rechecking => 'Re-checking the codes…';

  @override
  String get clearFailReplay => 'Not available for replays.';

  @override
  String get clearFailUnreadable =>
      'Engine speed / vehicle speed cannot be read, so it is not safe to clear.';

  @override
  String clearFailEngine(Object rpm) {
    return 'The engine is running ($rpm rpm). Switch the engine off and keep the ignition on.';
  }

  @override
  String clearFailMoving(Object speed) {
    return 'The vehicle is moving ($speed km/h).';
  }

  @override
  String clearFailUpload(Object reason) {
    return 'Could not save the scan on the server: $reason';
  }

  @override
  String get otherProcedures => 'Other procedures';

  @override
  String get procedureUnavailable => 'Unavailable';

  @override
  String get srsNote => 'Airbag (SRS) codes are never cleared by this app.';

  @override
  String get autoStartAfterClear =>
      'Demo: start the engine automatically after clearing';

  @override
  String get monitorComplete => 'complete';

  @override
  String get monitorIncomplete => 'not complete';
}
