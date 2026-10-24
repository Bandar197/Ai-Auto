import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AutoMind AI'**
  String get appTitle;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {error}'**
  String errorGeneric(Object error);

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @exportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get exportJson;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get notAvailable;

  /// No description provided for @modeLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get modeLive;

  /// No description provided for @modeDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get modeDemo;

  /// No description provided for @modeReplay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get modeReplay;

  /// No description provided for @demoBanner.
  ///
  /// In en, this message translates to:
  /// **'DEMO — simulated data, not from a real vehicle'**
  String get demoBanner;

  /// No description provided for @replayBanner.
  ///
  /// In en, this message translates to:
  /// **'REPLAY of a {mode} recording'**
  String replayBanner(Object mode);

  /// No description provided for @simulatorLabel.
  ///
  /// In en, this message translates to:
  /// **'Simulator'**
  String get simulatorLabel;

  /// No description provided for @demoWatermark.
  ///
  /// In en, this message translates to:
  /// **'DEMO'**
  String get demoWatermark;

  /// No description provided for @replayWatermark.
  ///
  /// In en, this message translates to:
  /// **'REPLAY'**
  String get replayWatermark;

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'Understand your car'**
  String get onboardingTitle1;

  /// No description provided for @onboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'Plug an ELM327 OBD-II adapter into your car and read real fault codes and live sensor data.'**
  String get onboardingBody1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'Evidence, not guesses'**
  String get onboardingTitle2;

  /// No description provided for @onboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'Every finding shows what was measured and what was inferred, with tests to confirm before buying parts.'**
  String get onboardingBody2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Works offline'**
  String get onboardingTitle3;

  /// No description provided for @onboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi adapters may cut your internet. Scans are saved on the phone and uploaded later.'**
  String get onboardingBody3;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @continueOffline.
  ///
  /// In en, this message translates to:
  /// **'Continue without an account'**
  String get continueOffline;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get register;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @acceptTerms.
  ///
  /// In en, this message translates to:
  /// **'I accept the Terms of Service (v{version})'**
  String acceptTerms(Object version);

  /// No description provided for @acceptPrivacy.
  ///
  /// In en, this message translates to:
  /// **'I accept the Privacy Policy (v{version}) and the processing of my vehicle data'**
  String acceptPrivacy(Object version);

  /// No description provided for @consentRequired.
  ///
  /// In en, this message translates to:
  /// **'Both consents are required to create an account.'**
  String get consentRequired;

  /// No description provided for @passwordPolicy.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters, different from your email.'**
  String get passwordPolicy;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'No account? Create one'**
  String get noAccount;

  /// No description provided for @haveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already registered? Log in'**
  String get haveAccount;

  /// No description provided for @mfaCode.
  ///
  /// In en, this message translates to:
  /// **'Authenticator code'**
  String get mfaCode;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get invalidEmail;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @vehicleNone.
  ///
  /// In en, this message translates to:
  /// **'No vehicle selected'**
  String get vehicleNone;

  /// No description provided for @addVehicle.
  ///
  /// In en, this message translates to:
  /// **'Add vehicle'**
  String get addVehicle;

  /// No description provided for @adapterLabel.
  ///
  /// In en, this message translates to:
  /// **'Adapter'**
  String get adapterLabel;

  /// No description provided for @ecuLabel.
  ///
  /// In en, this message translates to:
  /// **'Car (ECU)'**
  String get ecuLabel;

  /// No description provided for @healthScore.
  ///
  /// In en, this message translates to:
  /// **'Vehicle health'**
  String get healthScore;

  /// No description provided for @healthUnknown.
  ///
  /// In en, this message translates to:
  /// **'No diagnosis yet'**
  String get healthUnknown;

  /// No description provided for @healthBand_good.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get healthBand_good;

  /// No description provided for @healthBand_fair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get healthBand_fair;

  /// No description provided for @healthBand_attention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get healthBand_attention;

  /// No description provided for @healthBand_critical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get healthBand_critical;

  /// No description provided for @dtcCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No fault codes} =1{1 fault code} other{{count} fault codes}}'**
  String dtcCount(int count);

  /// No description provided for @importantAlerts.
  ///
  /// In en, this message translates to:
  /// **'Important alerts'**
  String get importantAlerts;

  /// No description provided for @noAlerts.
  ///
  /// In en, this message translates to:
  /// **'No important alerts'**
  String get noAlerts;

  /// No description provided for @lastScan.
  ///
  /// In en, this message translates to:
  /// **'Last scan: {when}'**
  String lastScan(Object when);

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get never;

  /// No description provided for @startScan.
  ///
  /// In en, this message translates to:
  /// **'Start scan'**
  String get startScan;

  /// No description provided for @liveData.
  ///
  /// In en, this message translates to:
  /// **'Live data'**
  String get liveData;

  /// No description provided for @maintenanceHistory.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get maintenanceHistory;

  /// No description provided for @sessionsHistory.
  ///
  /// In en, this message translates to:
  /// **'Scan history'**
  String get sessionsHistory;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @pendingUploads.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 scan waiting to upload} other{{count} scans waiting to upload}}'**
  String pendingUploads(int count);

  /// No description provided for @uploadNow.
  ///
  /// In en, this message translates to:
  /// **'Upload now'**
  String get uploadNow;

  /// No description provided for @adapterDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get adapterDisconnected;

  /// No description provided for @adapterConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get adapterConnecting;

  /// No description provided for @adapterConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get adapterConnected;

  /// No description provided for @adapterError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get adapterError;

  /// No description provided for @ecuUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not checked'**
  String get ecuUnknown;

  /// No description provided for @ecuSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get ecuSearching;

  /// No description provided for @ecuConnected.
  ///
  /// In en, this message translates to:
  /// **'Responding'**
  String get ecuConnected;

  /// No description provided for @ecuNoResponse.
  ///
  /// In en, this message translates to:
  /// **'No response'**
  String get ecuNoResponse;

  /// No description provided for @ecuBusError.
  ///
  /// In en, this message translates to:
  /// **'Bus error'**
  String get ecuBusError;

  /// No description provided for @linkIdle.
  ///
  /// In en, this message translates to:
  /// **'Choose how to connect.'**
  String get linkIdle;

  /// No description provided for @linkConnectingAdapter.
  ///
  /// In en, this message translates to:
  /// **'Phone → adapter: connecting…'**
  String get linkConnectingAdapter;

  /// No description provided for @linkAdapterUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The phone cannot reach the adapter. Check that you joined the adapter\'s Wi-Fi (or Bluetooth is on) and the IP/port.'**
  String get linkAdapterUnreachable;

  /// No description provided for @linkAdapterTimeout.
  ///
  /// In en, this message translates to:
  /// **'The adapter did not answer in time (phone → adapter link).'**
  String get linkAdapterTimeout;

  /// No description provided for @linkAdapterNotElm.
  ///
  /// In en, this message translates to:
  /// **'The device answered but is not an ELM327-compatible adapter.'**
  String get linkAdapterNotElm;

  /// No description provided for @linkInitializing.
  ///
  /// In en, this message translates to:
  /// **'Adapter found, initialising…'**
  String get linkInitializing;

  /// No description provided for @linkSearchingProtocol.
  ///
  /// In en, this message translates to:
  /// **'Adapter → car: searching for the OBD protocol (ignition must be ON)…'**
  String get linkSearchingProtocol;

  /// No description provided for @linkEcuConnected.
  ///
  /// In en, this message translates to:
  /// **'Adapter and car are talking.'**
  String get linkEcuConnected;

  /// No description provided for @linkEcuNoResponse.
  ///
  /// In en, this message translates to:
  /// **'The adapter works but the car did not answer. Turn the ignition ON (or start the engine) and check the adapter is fully seated.'**
  String get linkEcuNoResponse;

  /// No description provided for @linkEcuBusError.
  ///
  /// In en, this message translates to:
  /// **'The adapter reports a bus error on the car side. Try another protocol or check wiring.'**
  String get linkEcuBusError;

  /// No description provided for @linkLost.
  ///
  /// In en, this message translates to:
  /// **'Connection to the adapter was lost.'**
  String get linkLost;

  /// No description provided for @linkReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get linkReconnecting;

  /// No description provided for @linkReconnected.
  ///
  /// In en, this message translates to:
  /// **'Reconnected.'**
  String get linkReconnected;

  /// No description provided for @linkDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected.'**
  String get linkDisconnected;

  /// No description provided for @connectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectTitle;

  /// No description provided for @transportWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get transportWifi;

  /// No description provided for @transportBle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth LE'**
  String get transportBle;

  /// No description provided for @wifiHost.
  ///
  /// In en, this message translates to:
  /// **'Adapter IP'**
  String get wifiHost;

  /// No description provided for @wifiPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get wifiPort;

  /// No description provided for @protocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get protocol;

  /// No description provided for @protocolAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get protocolAuto;

  /// No description provided for @bleScan.
  ///
  /// In en, this message translates to:
  /// **'Scan for adapters'**
  String get bleScan;

  /// No description provided for @bleScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get bleScanning;

  /// No description provided for @bleNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No Bluetooth adapters found yet.'**
  String get bleNoDevices;

  /// No description provided for @bleNote.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth LE adapters are found by scanning — no pairing in system settings needed.'**
  String get bleNote;

  /// No description provided for @transportClassic.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Classic'**
  String get transportClassic;

  /// No description provided for @transportSerial.
  ///
  /// In en, this message translates to:
  /// **'Serial / COM (Bluetooth Classic or USB)'**
  String get transportSerial;

  /// No description provided for @classicIosNote.
  ///
  /// In en, this message translates to:
  /// **'iPhone does not allow Bluetooth Classic (SPP) OBD adapters in normal apps (Apple requires MFi accessories). Use a Bluetooth LE or Wi-Fi adapter.'**
  String get classicIosNote;

  /// No description provided for @classicAndroidNote.
  ///
  /// In en, this message translates to:
  /// **'Pair the adapter first in Android Settings → Bluetooth (PIN usually 1234 or 0000), then choose it here.'**
  String get classicAndroidNote;

  /// No description provided for @classicDesktopNote.
  ///
  /// In en, this message translates to:
  /// **'Windows: pair the adapter in Settings → Bluetooth & devices (PIN usually 1234 or 0000). Windows then creates an outgoing COM port — choose it here. USB adapters also appear as COM ports.'**
  String get classicDesktopNote;

  /// No description provided for @classicNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No paired adapters / COM ports found.'**
  String get classicNoDevices;

  /// No description provided for @classicBluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off or not available.'**
  String get classicBluetoothOff;

  /// No description provided for @baudRate.
  ///
  /// In en, this message translates to:
  /// **'Baud rate'**
  String get baudRate;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @lastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used'**
  String get lastUsed;

  /// No description provided for @wifiInternetNote.
  ///
  /// In en, this message translates to:
  /// **'When the phone joins the adapter\'s Wi-Fi it may lose internet. The scan is saved on the phone and uploaded automatically later.'**
  String get wifiInternetNote;

  /// No description provided for @demoScenarios.
  ///
  /// In en, this message translates to:
  /// **'Demo scenarios'**
  String get demoScenarios;

  /// No description provided for @demoExplain.
  ///
  /// In en, this message translates to:
  /// **'Demo uses a built-in simulator. Results are clearly labelled DEMO.'**
  String get demoExplain;

  /// No description provided for @replayFromFile.
  ///
  /// In en, this message translates to:
  /// **'Open recording file'**
  String get replayFromFile;

  /// No description provided for @replayFromServer.
  ///
  /// In en, this message translates to:
  /// **'Recordings on the server'**
  String get replayFromServer;

  /// No description provided for @replayLocal.
  ///
  /// In en, this message translates to:
  /// **'Recordings on this phone'**
  String get replayLocal;

  /// No description provided for @noRecordings.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet.'**
  String get noRecordings;

  /// No description provided for @connectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectButton;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @simulateEngineOff.
  ///
  /// In en, this message translates to:
  /// **'Simulate engine off'**
  String get simulateEngineOff;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanTitle;

  /// No description provided for @stepAdapter.
  ///
  /// In en, this message translates to:
  /// **'Connect to adapter'**
  String get stepAdapter;

  /// No description provided for @stepInit.
  ///
  /// In en, this message translates to:
  /// **'Initialise adapter'**
  String get stepInit;

  /// No description provided for @stepProtocol.
  ///
  /// In en, this message translates to:
  /// **'Detect protocol'**
  String get stepProtocol;

  /// No description provided for @stepEcu.
  ///
  /// In en, this message translates to:
  /// **'Find control units'**
  String get stepEcu;

  /// No description provided for @stepSupported.
  ///
  /// In en, this message translates to:
  /// **'Read supported sensors'**
  String get stepSupported;

  /// No description provided for @stepVin.
  ///
  /// In en, this message translates to:
  /// **'Read VIN'**
  String get stepVin;

  /// No description provided for @stepDtcs.
  ///
  /// In en, this message translates to:
  /// **'Read fault codes (03/07/0A)'**
  String get stepDtcs;

  /// No description provided for @stepFreeze.
  ///
  /// In en, this message translates to:
  /// **'Read freeze frame'**
  String get stepFreeze;

  /// No description provided for @stepCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture live data'**
  String get stepCapture;

  /// No description provided for @stepUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload & diagnose'**
  String get stepUpload;

  /// No description provided for @captureProgress.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s left'**
  String captureProgress(int seconds);

  /// No description provided for @viewReport.
  ///
  /// In en, this message translates to:
  /// **'View report'**
  String get viewReport;

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan stopped: {reason}'**
  String scanFailed(Object reason);

  /// No description provided for @cancelScan.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get cancelScan;

  /// No description provided for @scanSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get scanSkipped;

  /// No description provided for @scanQueued.
  ///
  /// In en, this message translates to:
  /// **'Saved — will upload when online'**
  String get scanQueued;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnosis report'**
  String get reportTitle;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @technicianSummary.
  ///
  /// In en, this message translates to:
  /// **'For the technician'**
  String get technicianSummary;

  /// No description provided for @dtcsTitle.
  ///
  /// In en, this message translates to:
  /// **'Fault codes'**
  String get dtcsTitle;

  /// No description provided for @noDtcs.
  ///
  /// In en, this message translates to:
  /// **'No fault codes reported.'**
  String get noDtcs;

  /// No description provided for @findings.
  ///
  /// In en, this message translates to:
  /// **'Findings'**
  String get findings;

  /// No description provided for @severity_low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get severity_low;

  /// No description provided for @severity_medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get severity_medium;

  /// No description provided for @severity_high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get severity_high;

  /// No description provided for @severity_critical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get severity_critical;

  /// No description provided for @severity_info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get severity_info;

  /// No description provided for @confidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence {value}%'**
  String confidence(int value);

  /// No description provided for @probableCauses.
  ///
  /// In en, this message translates to:
  /// **'Probable causes'**
  String get probableCauses;

  /// No description provided for @likelihood.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String likelihood(int value);

  /// No description provided for @evidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get evidence;

  /// No description provided for @measured.
  ///
  /// In en, this message translates to:
  /// **'Measured'**
  String get measured;

  /// No description provided for @inferred.
  ///
  /// In en, this message translates to:
  /// **'Inferred'**
  String get inferred;

  /// No description provided for @observed.
  ///
  /// In en, this message translates to:
  /// **'Observed'**
  String get observed;

  /// No description provided for @expected.
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get expected;

  /// No description provided for @tests.
  ///
  /// In en, this message translates to:
  /// **'Recommended tests'**
  String get tests;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @partsToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Parts (confirm first)'**
  String get partsToConfirm;

  /// No description provided for @requiresConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Requires confirmation'**
  String get requiresConfirmation;

  /// No description provided for @missingData.
  ///
  /// In en, this message translates to:
  /// **'Missing data'**
  String get missingData;

  /// No description provided for @disclaimers.
  ///
  /// In en, this message translates to:
  /// **'Disclaimers'**
  String get disclaimers;

  /// No description provided for @systemStatus.
  ///
  /// In en, this message translates to:
  /// **'Systems'**
  String get systemStatus;

  /// No description provided for @dataQuality.
  ///
  /// In en, this message translates to:
  /// **'Data quality'**
  String get dataQuality;

  /// No description provided for @offlineReportNote.
  ///
  /// In en, this message translates to:
  /// **'Offline: showing fault-code meanings from the built-in knowledge base only. Full analysis needs the server; this scan is queued for upload.'**
  String get offlineReportNote;

  /// No description provided for @kbUnknownCode.
  ///
  /// In en, this message translates to:
  /// **'Description not in the knowledge base.'**
  String get kbUnknownCode;

  /// No description provided for @analyzeNow.
  ///
  /// In en, this message translates to:
  /// **'Analyse on server'**
  String get analyzeNow;

  /// No description provided for @freezeFrame.
  ///
  /// In en, this message translates to:
  /// **'Freeze frame'**
  String get freezeFrame;

  /// No description provided for @vinLabel.
  ///
  /// In en, this message translates to:
  /// **'VIN'**
  String get vinLabel;

  /// No description provided for @howTo.
  ///
  /// In en, this message translates to:
  /// **'How'**
  String get howTo;

  /// No description provided for @expectedResult.
  ///
  /// In en, this message translates to:
  /// **'Expected result'**
  String get expectedResult;

  /// No description provided for @liveTitle.
  ///
  /// In en, this message translates to:
  /// **'Live data'**
  String get liveTitle;

  /// No description provided for @chooseSignals.
  ///
  /// In en, this message translates to:
  /// **'Signals'**
  String get chooseSignals;

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// No description provided for @stopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopRecording;

  /// No description provided for @recordingSaved.
  ///
  /// In en, this message translates to:
  /// **'Recording saved'**
  String get recordingSaved;

  /// No description provided for @compareWith.
  ///
  /// In en, this message translates to:
  /// **'Compare with recording'**
  String get compareWith;

  /// No description provided for @clearCompare.
  ///
  /// In en, this message translates to:
  /// **'Remove comparison'**
  String get clearCompare;

  /// No description provided for @sampleRate.
  ///
  /// In en, this message translates to:
  /// **'{rate} samples/s'**
  String sampleRate(Object rate);

  /// No description provided for @outOfRange.
  ///
  /// In en, this message translates to:
  /// **'Out of range'**
  String get outOfRange;

  /// No description provided for @noSupportedSignals.
  ///
  /// In en, this message translates to:
  /// **'No supported signals reported by the car.'**
  String get noSupportedSignals;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected. Connect first.'**
  String get notConnected;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan history'**
  String get historyTitle;

  /// No description provided for @noSessions.
  ///
  /// In en, this message translates to:
  /// **'No scans yet.'**
  String get noSessions;

  /// No description provided for @localOnly.
  ///
  /// In en, this message translates to:
  /// **'On phone only'**
  String get localOnly;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get synced;

  /// No description provided for @vehiclesTitle.
  ///
  /// In en, this message translates to:
  /// **'Vehicles'**
  String get vehiclesTitle;

  /// No description provided for @make.
  ///
  /// In en, this message translates to:
  /// **'Make'**
  String get make;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @plate.
  ///
  /// In en, this message translates to:
  /// **'Plate'**
  String get plate;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @odometer.
  ///
  /// In en, this message translates to:
  /// **'Odometer (km)'**
  String get odometer;

  /// No description provided for @fuelTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Fuel type'**
  String get fuelTypeLabel;

  /// No description provided for @engineLabel.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get engineLabel;

  /// No description provided for @transmission.
  ///
  /// In en, this message translates to:
  /// **'Transmission'**
  String get transmission;

  /// No description provided for @selectVehicle.
  ///
  /// In en, this message translates to:
  /// **'Use this vehicle'**
  String get selectVehicle;

  /// No description provided for @maintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintenance log'**
  String get maintenanceTitle;

  /// No description provided for @addRecord.
  ///
  /// In en, this message translates to:
  /// **'Add record'**
  String get addRecord;

  /// No description provided for @serviceType.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get serviceType;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @cost.
  ///
  /// In en, this message translates to:
  /// **'Cost (SAR)'**
  String get cost;

  /// No description provided for @noMaintenance.
  ///
  /// In en, this message translates to:
  /// **'No maintenance records.'**
  String get noMaintenance;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @backendUrl.
  ///
  /// In en, this message translates to:
  /// **'Backend URL'**
  String get backendUrl;

  /// No description provided for @adapterSettings.
  ///
  /// In en, this message translates to:
  /// **'Adapter'**
  String get adapterSettings;

  /// No description provided for @commandTimeout.
  ///
  /// In en, this message translates to:
  /// **'Command timeout (ms)'**
  String get commandTimeout;

  /// No description provided for @searchTimeout.
  ///
  /// In en, this message translates to:
  /// **'Protocol search timeout (ms)'**
  String get searchTimeout;

  /// No description provided for @bleUuidOverride.
  ///
  /// In en, this message translates to:
  /// **'BLE UUID override (service / notify / write)'**
  String get bleUuidOverride;

  /// No description provided for @includeVin.
  ///
  /// In en, this message translates to:
  /// **'Include VIN in uploads'**
  String get includeVin;

  /// No description provided for @captureDuration.
  ///
  /// In en, this message translates to:
  /// **'Live capture during scan (s)'**
  String get captureDuration;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @notLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get notLoggedIn;

  /// No description provided for @clearDtcsTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear fault codes'**
  String get clearDtcsTitle;

  /// No description provided for @clearDtcsWarning.
  ///
  /// In en, this message translates to:
  /// **'Clearing codes turns off the check-engine light but does NOT fix the fault. All readiness monitors reset, so the car may fail an inspection until it completes a full drive cycle, and freeze-frame data is erased. Codes will return if the fault is still present.'**
  String get clearDtcsWarning;

  /// No description provided for @clearDtcsChecklist.
  ///
  /// In en, this message translates to:
  /// **'Engine OFF, ignition ON, vehicle stopped.'**
  String get clearDtcsChecklist;

  /// No description provided for @clearDtcsConfirm.
  ///
  /// In en, this message translates to:
  /// **'I understand — clear codes'**
  String get clearDtcsConfirm;

  /// No description provided for @clearCodesCount.
  ///
  /// In en, this message translates to:
  /// **'Clear {count} code(s)'**
  String clearCodesCount(int count);

  /// No description provided for @clearWillReturnNote.
  ///
  /// In en, this message translates to:
  /// **'Clearing turns the light off but does not fix the fault — codes return if the problem is real.'**
  String get clearWillReturnNote;

  /// No description provided for @extendedModulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Airbag / ABS modules'**
  String get extendedModulesTitle;

  /// No description provided for @extendedModulesIntro.
  ///
  /// In en, this message translates to:
  /// **'Reads fault codes from modules a normal scan does not reach — airbag (SRS), ABS and body control — over manufacturer diagnostics. Read-only.'**
  String get extendedModulesIntro;

  /// No description provided for @extendedScanCta.
  ///
  /// In en, this message translates to:
  /// **'Scan airbag / ABS modules'**
  String get extendedScanCta;

  /// No description provided for @extendedNeedsLive.
  ///
  /// In en, this message translates to:
  /// **'Available in live mode only (needs a real car).'**
  String get extendedNeedsLive;

  /// No description provided for @extendedNoModules.
  ///
  /// In en, this message translates to:
  /// **'No module answered. The addresses may need tuning for this car, or a security gateway is blocking access.'**
  String get extendedNoModules;

  /// No description provided for @extendedRefused.
  ///
  /// In en, this message translates to:
  /// **'Present, but it refused the request (may be gateway-protected).'**
  String get extendedRefused;

  /// No description provided for @extendedNoFaults.
  ///
  /// In en, this message translates to:
  /// **'No faults'**
  String get extendedNoFaults;

  /// No description provided for @extendedDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Module addresses are discovery starting points, confirmed per vehicle. Codes read here are over manufacturer diagnostics and should be verified on the car.'**
  String get extendedDisclaimer;

  /// No description provided for @extendedAirbagClearNote.
  ///
  /// In en, this message translates to:
  /// **'Clearing airbag codes is a separate, gated step: it is refused while a fault is active, and only after the repair is confirmed.'**
  String get extendedAirbagClearNote;

  /// No description provided for @explainTitle.
  ///
  /// In en, this message translates to:
  /// **'Explain code'**
  String get explainTitle;

  /// No description provided for @explainCta.
  ///
  /// In en, this message translates to:
  /// **'Explain this code'**
  String get explainCta;

  /// No description provided for @explainByAi.
  ///
  /// In en, this message translates to:
  /// **'AI explanation, grounded in the knowledge base.'**
  String get explainByAi;

  /// No description provided for @explainFromKb.
  ///
  /// In en, this message translates to:
  /// **'From the knowledge base.'**
  String get explainFromKb;

  /// No description provided for @explainOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline: shown from the built-in knowledge base.'**
  String get explainOffline;

  /// No description provided for @whatToCheck.
  ///
  /// In en, this message translates to:
  /// **'What to check first'**
  String get whatToCheck;

  /// No description provided for @explainVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get explainVideos;

  /// No description provided for @linkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link.'**
  String get linkOpenFailed;

  /// No description provided for @clearRequiresServer.
  ///
  /// In en, this message translates to:
  /// **'Clearing codes needs server approval. Connect to the internet and log in.'**
  String get clearRequiresServer;

  /// No description provided for @clearConditionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Refused: {reason}'**
  String clearConditionsFailed(Object reason);

  /// No description provided for @clearSuccess.
  ///
  /// In en, this message translates to:
  /// **'Fault codes cleared.'**
  String get clearSuccess;

  /// No description provided for @clearFailed.
  ///
  /// In en, this message translates to:
  /// **'The car did not confirm the clear request.'**
  String get clearFailed;

  /// No description provided for @clearRejected.
  ///
  /// In en, this message translates to:
  /// **'The server rejected the request: {reason}'**
  String clearRejected(Object reason);

  /// No description provided for @clearDemoNote.
  ///
  /// In en, this message translates to:
  /// **'Demo/simulator: no command reaches a real vehicle.'**
  String get clearDemoNote;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get selectAll;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'s'**
  String get seconds;

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify after clear'**
  String get verifyTitle;

  /// No description provided for @verifyOverall_problem_confirmed.
  ///
  /// In en, this message translates to:
  /// **'Real problem'**
  String get verifyOverall_problem_confirmed;

  /// No description provided for @verifyOverall_likely_resolved.
  ///
  /// In en, this message translates to:
  /// **'Most likely an old fault'**
  String get verifyOverall_likely_resolved;

  /// No description provided for @verifyOverall_verifying.
  ///
  /// In en, this message translates to:
  /// **'Verification in progress'**
  String get verifyOverall_verifying;

  /// No description provided for @verifyOverall_nothing_cleared.
  ///
  /// In en, this message translates to:
  /// **'Nothing to verify'**
  String get verifyOverall_nothing_cleared;

  /// No description provided for @verifyChecks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No check since clearing yet} =1{1 check since clearing} other{{count} checks since clearing}}'**
  String verifyChecks(int count);

  /// No description provided for @verifyCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get verifyCheckNow;

  /// No description provided for @verifyRunScan.
  ///
  /// In en, this message translates to:
  /// **'Full scan'**
  String get verifyRunScan;

  /// No description provided for @verifyClose.
  ///
  /// In en, this message translates to:
  /// **'End verification'**
  String get verifyClose;

  /// No description provided for @verifyClearedAt.
  ///
  /// In en, this message translates to:
  /// **'Cleared: {when}'**
  String verifyClearedAt(Object when);

  /// No description provided for @verifySourceServer.
  ///
  /// In en, this message translates to:
  /// **'Verdict from the AutoMind server'**
  String get verifySourceServer;

  /// No description provided for @verifySourceLocal.
  ///
  /// In en, this message translates to:
  /// **'Offline verdict calculated on the phone (same rules as the server)'**
  String get verifySourceLocal;

  /// No description provided for @verifyNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get verifyNextStep;

  /// No description provided for @verifyBeforeCodes.
  ///
  /// In en, this message translates to:
  /// **'Saved before clearing'**
  String get verifyBeforeCodes;

  /// No description provided for @verifyHomeCard.
  ///
  /// In en, this message translates to:
  /// **'Clear & verify'**
  String get verifyHomeCard;

  /// No description provided for @verifyNone.
  ///
  /// In en, this message translates to:
  /// **'No clear to verify yet.'**
  String get verifyNone;

  /// No description provided for @verifyHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'If a cleared code comes back, you have a real problem. If it stays away after the car re-runs its self-tests, it was most likely an old fault.'**
  String get verifyHowItWorks;

  /// No description provided for @checkLabel.
  ///
  /// In en, this message translates to:
  /// **'Check #{n}'**
  String checkLabel(int n);

  /// No description provided for @noCodesInCheck.
  ///
  /// In en, this message translates to:
  /// **'No codes'**
  String get noCodesInCheck;

  /// No description provided for @viewVerification.
  ///
  /// In en, this message translates to:
  /// **'View verification'**
  String get viewVerification;

  /// No description provided for @clearErases.
  ///
  /// In en, this message translates to:
  /// **'Clearing will erase'**
  String get clearErases;

  /// No description provided for @clearErasesFreeze.
  ///
  /// In en, this message translates to:
  /// **'The freeze frame (conditions when the fault happened). A copy stays in the saved scan.'**
  String get clearErasesFreeze;

  /// No description provided for @clearErasesReadiness.
  ///
  /// In en, this message translates to:
  /// **'All readiness monitors restart from zero:'**
  String get clearErasesReadiness;

  /// No description provided for @clearScanSaved.
  ///
  /// In en, this message translates to:
  /// **'The scan (codes + freeze frame) is saved on the server.'**
  String get clearScanSaved;

  /// No description provided for @clearScanNotSaved.
  ///
  /// In en, this message translates to:
  /// **'The scan will be saved on the server first — clearing is only allowed after the codes are saved.'**
  String get clearScanNotSaved;

  /// No description provided for @clearNoReport.
  ///
  /// In en, this message translates to:
  /// **'Run a scan first: the codes must be saved before clearing.'**
  String get clearNoReport;

  /// No description provided for @clearPhase_checking.
  ///
  /// In en, this message translates to:
  /// **'Checking engine off and speed 0…'**
  String get clearPhase_checking;

  /// No description provided for @clearPhase_uploading.
  ///
  /// In en, this message translates to:
  /// **'Saving the scan on the server…'**
  String get clearPhase_uploading;

  /// No description provided for @clearPhase_requesting.
  ///
  /// In en, this message translates to:
  /// **'Requesting server approval…'**
  String get clearPhase_requesting;

  /// No description provided for @clearPhase_clearing.
  ///
  /// In en, this message translates to:
  /// **'Clearing codes…'**
  String get clearPhase_clearing;

  /// No description provided for @clearPhase_waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting a few seconds…'**
  String get clearPhase_waiting;

  /// No description provided for @clearPhase_rechecking.
  ///
  /// In en, this message translates to:
  /// **'Re-checking the codes…'**
  String get clearPhase_rechecking;

  /// No description provided for @clearFailReplay.
  ///
  /// In en, this message translates to:
  /// **'Not available for replays.'**
  String get clearFailReplay;

  /// No description provided for @clearFailUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Engine speed / vehicle speed cannot be read, so it is not safe to clear.'**
  String get clearFailUnreadable;

  /// No description provided for @clearFailEngine.
  ///
  /// In en, this message translates to:
  /// **'The engine is running ({rpm} rpm). Switch the engine off and keep the ignition on.'**
  String clearFailEngine(Object rpm);

  /// No description provided for @clearFailMoving.
  ///
  /// In en, this message translates to:
  /// **'The vehicle is moving ({speed} km/h).'**
  String clearFailMoving(Object speed);

  /// No description provided for @clearFailUpload.
  ///
  /// In en, this message translates to:
  /// **'Could not save the scan on the server: {reason}'**
  String clearFailUpload(Object reason);

  /// No description provided for @otherProcedures.
  ///
  /// In en, this message translates to:
  /// **'Other procedures'**
  String get otherProcedures;

  /// No description provided for @procedureUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get procedureUnavailable;

  /// No description provided for @srsNote.
  ///
  /// In en, this message translates to:
  /// **'Airbag (SRS) codes are never cleared by this app.'**
  String get srsNote;

  /// No description provided for @autoStartAfterClear.
  ///
  /// In en, this message translates to:
  /// **'Demo: start the engine automatically after clearing'**
  String get autoStartAfterClear;

  /// No description provided for @monitorComplete.
  ///
  /// In en, this message translates to:
  /// **'complete'**
  String get monitorComplete;

  /// No description provided for @monitorIncomplete.
  ///
  /// In en, this message translates to:
  /// **'not complete'**
  String get monitorIncomplete;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
