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
  /// **'Super Scanner'**
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

  /// No description provided for @deleteScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this scan?'**
  String get deleteScanTitle;

  /// No description provided for @deleteScanBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the saved scan and its recording from this phone. Reports already uploaded stay on the server.'**
  String get deleteScanBody;

  /// No description provided for @deleteScanDone.
  ///
  /// In en, this message translates to:
  /// **'Scan deleted.'**
  String get deleteScanDone;

  /// No description provided for @knowledgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Guide & tips'**
  String get knowledgeTitle;

  /// No description provided for @knowledgeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What the warning lights mean, how each system is read, and practical maintenance tips.'**
  String get knowledgeSubtitle;

  /// No description provided for @reportModulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Module scan (airbag / ABS / body)'**
  String get reportModulesTitle;

  /// No description provided for @moduleReadCodes.
  ///
  /// In en, this message translates to:
  /// **'Stored codes'**
  String get moduleReadCodes;

  /// No description provided for @moduleNoCodes.
  ///
  /// In en, this message translates to:
  /// **'Read — no stored codes'**
  String get moduleNoCodes;

  /// No description provided for @moduleRefused.
  ///
  /// In en, this message translates to:
  /// **'Present but refused the read (security gateway)'**
  String get moduleRefused;

  /// No description provided for @moduleNoResponse.
  ///
  /// In en, this message translates to:
  /// **'No response — couldn\'t verify'**
  String get moduleNoResponse;

  /// No description provided for @moduleAirbagUnverified.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the airbag (SRS). If the light is on it may be a real fault — see a specialist.'**
  String get moduleAirbagUnverified;

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

  /// No description provided for @exportEvidence.
  ///
  /// In en, this message translates to:
  /// **'Export evidence bundle (ZIP)'**
  String get exportEvidence;

  /// No description provided for @exportEvidenceNoRecording.
  ///
  /// In en, this message translates to:
  /// **'No local recording for this scan — the evidence bundle needs the saved session.'**
  String get exportEvidenceNoRecording;

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

  /// No description provided for @otherOption.
  ///
  /// In en, this message translates to:
  /// **'Other…'**
  String get otherOption;

  /// No description provided for @controllersCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Controller catalogue'**
  String get controllersCatalogTitle;

  /// No description provided for @controllersCatalogNote.
  ///
  /// In en, this message translates to:
  /// **'Reference list of control-module names per manufacturer. These are UNVERIFIED catalogue entries — not CAN addresses and not proof a module is readable on your car. Readable modules come from an actual scan.'**
  String get controllersCatalogNote;

  /// No description provided for @unverifiedCatalogEntry.
  ///
  /// In en, this message translates to:
  /// **'Unverified catalog entry'**
  String get unverifiedCatalogEntry;

  /// No description provided for @allMakes.
  ///
  /// In en, this message translates to:
  /// **'All makes'**
  String get allMakes;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @deepScanCta.
  ///
  /// In en, this message translates to:
  /// **'Scan all approved addresses for this car'**
  String get deepScanCta;

  /// No description provided for @deepScanNote.
  ///
  /// In en, this message translates to:
  /// **'Reads (read-only) every module address in the app\'s compatibility list for your car\'s make. No blind address scanning. Addresses marked “unverified” have not yet been confirmed on a real car.'**
  String get deepScanNote;

  /// No description provided for @fullScanFindMore.
  ///
  /// In en, this message translates to:
  /// **'Expected a fault (e.g. airbag) that didn\'t show? Try deep discovery.'**
  String get fullScanFindMore;

  /// No description provided for @systemUnverified.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify this system — its module did not respond. Not read as healthy.'**
  String get systemUnverified;

  /// No description provided for @airbagUnverified.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the airbag (SRS) system — specialist diagnosis needed. If the airbag light is on, it may be a real fault.'**
  String get airbagUnverified;

  /// No description provided for @fullScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Full scan by system'**
  String get fullScanTitle;

  /// No description provided for @fullScanCta.
  ///
  /// In en, this message translates to:
  /// **'Start full scan'**
  String get fullScanCta;

  /// No description provided for @fullScanChecking.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get fullScanChecking;

  /// No description provided for @fullScanAllClear.
  ///
  /// In en, this message translates to:
  /// **'No fault codes found in the systems scanned.'**
  String get fullScanAllClear;

  /// No description provided for @fullScanSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} fault code(s) found'**
  String fullScanSummary(int count);

  /// No description provided for @fullScanUnverifiedNote.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify {count} system(s) — not shown as healthy.'**
  String fullScanUnverifiedNote(int count);

  /// No description provided for @fullScanCoverageNote.
  ///
  /// In en, this message translates to:
  /// **'Engine, emissions, transmission, electrical and network come from the standard scan. Airbag, ABS and body are read per module and depend on your car\'s addresses being supported; a security gateway can block some modules.'**
  String get fullScanCoverageNote;

  /// No description provided for @fullScanSaveReport.
  ///
  /// In en, this message translates to:
  /// **'Save & view report'**
  String get fullScanSaveReport;

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
  /// **'Airbag (SRS) codes are cleared only on a verified module with a documented clear function and server approval for this car — never otherwise. Crash data is never cleared.'**
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

  /// No description provided for @adapterCapsTitle.
  ///
  /// In en, this message translates to:
  /// **'Adapter capabilities'**
  String get adapterCapsTitle;

  /// No description provided for @adapterCapsIntro.
  ///
  /// In en, this message translates to:
  /// **'Tests what this adapter really supports — by its behaviour, not its name. Only adapter (AT) commands and read-only requests are sent; nothing is written to the car.'**
  String get adapterCapsIntro;

  /// No description provided for @adapterCapsRun.
  ///
  /// In en, this message translates to:
  /// **'Run test'**
  String get adapterCapsRun;

  /// No description provided for @adapterCapsRerun.
  ///
  /// In en, this message translates to:
  /// **'Test again'**
  String get adapterCapsRerun;

  /// No description provided for @adapterCapsNotRun.
  ///
  /// In en, this message translates to:
  /// **'Not tested yet on this connection.'**
  String get adapterCapsNotRun;

  /// No description provided for @adapterCapsNeedConnection.
  ///
  /// In en, this message translates to:
  /// **'Connect to an adapter first.'**
  String get adapterCapsNeedConnection;

  /// No description provided for @adapterCapsReplay.
  ///
  /// In en, this message translates to:
  /// **'Not available in replay mode.'**
  String get adapterCapsReplay;

  /// No description provided for @adapterCapsBusy.
  ///
  /// In en, this message translates to:
  /// **'Wait for the connection to finish.'**
  String get adapterCapsBusy;

  /// No description provided for @adapterCapsIdleNote.
  ///
  /// In en, this message translates to:
  /// **'Stop live data and scans before testing.'**
  String get adapterCapsIdleNote;

  /// No description provided for @adapterCapsNoVehicle.
  ///
  /// In en, this message translates to:
  /// **'No vehicle answered — header, filter and multi-frame tests need the ignition on.'**
  String get adapterCapsNoVehicle;

  /// No description provided for @adapterCapsSimulator.
  ///
  /// In en, this message translates to:
  /// **'Simulator: these results describe the simulator, not a real adapter.'**
  String get adapterCapsSimulator;

  /// No description provided for @adapterCapsPass.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get adapterCapsPass;

  /// No description provided for @adapterCapsFail.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get adapterCapsFail;

  /// No description provided for @adapterCapsUntested.
  ///
  /// In en, this message translates to:
  /// **'Not tested'**
  String get adapterCapsUntested;

  /// No description provided for @adapterCapsBehavioral.
  ///
  /// In en, this message translates to:
  /// **'verified by behaviour'**
  String get adapterCapsBehavioral;

  /// No description provided for @adapterCapsAcceptedOnly.
  ///
  /// In en, this message translates to:
  /// **'command accepted only'**
  String get adapterCapsAcceptedOnly;

  /// No description provided for @adapterCapsRawLog.
  ///
  /// In en, this message translates to:
  /// **'Test log (raw)'**
  String get adapterCapsRawLog;

  /// No description provided for @adapterCapsCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy JSON'**
  String get adapterCapsCopy;

  /// No description provided for @adapterCapsCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get adapterCapsCopied;

  /// No description provided for @adapterCapsName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get adapterCapsName;

  /// No description provided for @adapterCapsFirmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get adapterCapsFirmware;

  /// No description provided for @adapterCapsVoltage.
  ///
  /// In en, this message translates to:
  /// **'Voltage'**
  String get adapterCapsVoltage;

  /// No description provided for @adapterCapsProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get adapterCapsProtocol;

  /// No description provided for @adapterCapsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get adapterCapsConnection;

  /// No description provided for @adapterCapsError.
  ///
  /// In en, this message translates to:
  /// **'Test failed: {error}'**
  String adapterCapsError(String error);

  /// No description provided for @capHeaders.
  ///
  /// In en, this message translates to:
  /// **'CAN headers (ATH1)'**
  String get capHeaders;

  /// No description provided for @capFilters.
  ///
  /// In en, this message translates to:
  /// **'Receive filter (ATCRA)'**
  String get capFilters;

  /// No description provided for @capCanFormatting.
  ///
  /// In en, this message translates to:
  /// **'CAN formatting (ATCAF1)'**
  String get capCanFormatting;

  /// No description provided for @capIsoTp.
  ///
  /// In en, this message translates to:
  /// **'ISO-TP transport'**
  String get capIsoTp;

  /// No description provided for @capMultiFrame.
  ///
  /// In en, this message translates to:
  /// **'Multi-frame responses'**
  String get capMultiFrame;

  /// No description provided for @capFlowControl.
  ///
  /// In en, this message translates to:
  /// **'Flow control (ATFCSM)'**
  String get capFlowControl;

  /// No description provided for @capProtocolSwitching.
  ///
  /// In en, this message translates to:
  /// **'Protocol switching'**
  String get capProtocolSwitching;

  /// No description provided for @moduleAddrUnverified.
  ///
  /// In en, this message translates to:
  /// **'unverified address'**
  String get moduleAddrUnverified;

  /// No description provided for @interruptedBanner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session was cut short (app closed or link lost).} other{{count} sessions were cut short (app closed or link lost).}} Its data up to that moment was kept on this device.'**
  String interruptedBanner(int count);

  /// No description provided for @recoverCta.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get recoverCta;

  /// No description provided for @recoveredDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session recovered} other{{count} sessions recovered}}'**
  String recoveredDone(int count);

  /// No description provided for @interruptedTag.
  ///
  /// In en, this message translates to:
  /// **'INTERRUPTED'**
  String get interruptedTag;

  /// No description provided for @interruptedReportNote.
  ///
  /// In en, this message translates to:
  /// **'This session was interrupted. It contains only the data captured before it stopped — missing systems were not checked, not \"healthy\".'**
  String get interruptedReportNote;

  /// No description provided for @importSession.
  ///
  /// In en, this message translates to:
  /// **'Import session'**
  String get importSession;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'Session imported'**
  String get importDone;

  /// No description provided for @importDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This session is already in your history'**
  String get importDuplicate;

  /// No description provided for @importTampered.
  ///
  /// In en, this message translates to:
  /// **'Refused: the evidence bundle was modified (SHA-256 mismatch: {files})'**
  String importTampered(String files);

  /// No description provided for @importInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not an AutoMind session file'**
  String get importInvalid;

  /// No description provided for @importedTag.
  ///
  /// In en, this message translates to:
  /// **'IMPORTED'**
  String get importedTag;

  /// No description provided for @compareTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare sessions'**
  String get compareTitle;

  /// No description provided for @compareBefore.
  ///
  /// In en, this message translates to:
  /// **'Earlier session'**
  String get compareBefore;

  /// No description provided for @compareAfter.
  ///
  /// In en, this message translates to:
  /// **'Later session'**
  String get compareAfter;

  /// No description provided for @compareNeedTwo.
  ///
  /// In en, this message translates to:
  /// **'Save at least two sessions to compare.'**
  String get compareNeedTwo;

  /// No description provided for @compareNew.
  ///
  /// In en, this message translates to:
  /// **'New codes'**
  String get compareNew;

  /// No description provided for @compareResolved.
  ///
  /// In en, this message translates to:
  /// **'Gone — confirmed by a successful read'**
  String get compareResolved;

  /// No description provided for @comparePersisting.
  ///
  /// In en, this message translates to:
  /// **'Still present'**
  String get comparePersisting;

  /// No description provided for @compareUnverified.
  ///
  /// In en, this message translates to:
  /// **'Not checked in the later session (module/OBD not read) — not counted as fixed'**
  String get compareUnverified;

  /// No description provided for @compareModules.
  ///
  /// In en, this message translates to:
  /// **'Module read changes'**
  String get compareModules;

  /// No description provided for @compareMixedModes.
  ///
  /// In en, this message translates to:
  /// **'One session is DEMO and the other LIVE — compare with care.'**
  String get compareMixedModes;

  /// No description provided for @compareNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No differences in fault codes.'**
  String get compareNoChanges;

  /// No description provided for @compareNotRead.
  ///
  /// In en, this message translates to:
  /// **'not attempted'**
  String get compareNotRead;

  /// No description provided for @exportFolder.
  ///
  /// In en, this message translates to:
  /// **'Export folder'**
  String get exportFolder;

  /// No description provided for @exportFolderDefault.
  ///
  /// In en, this message translates to:
  /// **'App folder (default)'**
  String get exportFolderDefault;

  /// No description provided for @exportFolderReset.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get exportFolderReset;

  /// No description provided for @clearCanTitle.
  ///
  /// In en, this message translates to:
  /// **'Can be cleared'**
  String get clearCanTitle;

  /// No description provided for @clearCannotTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot be cleared here'**
  String get clearCannotTitle;

  /// No description provided for @clearNoneClearable.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this scan can be cleared right now.'**
  String get clearNoneClearable;

  /// No description provided for @clearPermanentNote.
  ///
  /// In en, this message translates to:
  /// **'Permanent codes ({codes}) are not erased by clearing — they go by themselves once the related self-test passes.'**
  String clearPermanentNote(String codes);

  /// No description provided for @clearSelectedCta.
  ///
  /// In en, this message translates to:
  /// **'Clear selected ({count})'**
  String clearSelectedCta(int count);

  /// No description provided for @clearConsentTargets.
  ///
  /// In en, this message translates to:
  /// **'You are about to clear:'**
  String get clearConsentTargets;

  /// No description provided for @clearBatteryAdvice.
  ///
  /// In en, this message translates to:
  /// **'Battery: {volts} V — keep ≥ 12 V during clearing (connect a charger if lower).'**
  String clearBatteryAdvice(String volts);

  /// No description provided for @clearIgnitionOn.
  ///
  /// In en, this message translates to:
  /// **'Ignition ON (car answering)'**
  String get clearIgnitionOn;

  /// No description provided for @clearOfflineNote.
  ///
  /// In en, this message translates to:
  /// **'Offline: the engine clear is recorded in this device\'s audit log. Clearing other modules needs a server approval.'**
  String get clearOfflineNote;

  /// No description provided for @clearResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Result after re-reading'**
  String get clearResultsTitle;

  /// No description provided for @clearCodeVsLamp.
  ///
  /// In en, this message translates to:
  /// **'\"Code cleared\" means the module no longer reports it. It does not prove the warning lamp is off.'**
  String get clearCodeVsLamp;

  /// No description provided for @clearLampByCar.
  ///
  /// In en, this message translates to:
  /// **'The car reports the engine lamp (MIL) is OFF.'**
  String get clearLampByCar;

  /// No description provided for @clearLampConfirmCta.
  ///
  /// In en, this message translates to:
  /// **'I can see the lamp is off'**
  String get clearLampConfirmCta;

  /// No description provided for @clearLampConfirmed.
  ///
  /// In en, this message translates to:
  /// **'You confirmed the lamp is off.'**
  String get clearLampConfirmed;

  /// No description provided for @clearLampUnknown.
  ///
  /// In en, this message translates to:
  /// **'Lamp state not confirmed yet.'**
  String get clearLampUnknown;

  /// No description provided for @clearOpenVerification.
  ///
  /// In en, this message translates to:
  /// **'Follow up (verification)'**
  String get clearOpenVerification;

  /// No description provided for @clearSnapshotKept.
  ///
  /// In en, this message translates to:
  /// **'A permanent copy of everything before the clear was saved on this device.'**
  String get clearSnapshotKept;

  /// No description provided for @ctx_allowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get ctx_allowed;

  /// No description provided for @ctx_unsupported_by_hardware.
  ///
  /// In en, this message translates to:
  /// **'Not supported by this adapter'**
  String get ctx_unsupported_by_hardware;

  /// No description provided for @ctx_unsupported_by_vehicle.
  ///
  /// In en, this message translates to:
  /// **'Not supported for this car'**
  String get ctx_unsupported_by_vehicle;

  /// No description provided for @ctx_requires_oem_authorization.
  ///
  /// In en, this message translates to:
  /// **'Needs manufacturer / server authorization'**
  String get ctx_requires_oem_authorization;

  /// No description provided for @ctx_active_fault_not_clearable.
  ///
  /// In en, this message translates to:
  /// **'Active fault — cannot be cleared'**
  String get ctx_active_fault_not_clearable;

  /// No description provided for @ctx_crash_data_specialist.
  ///
  /// In en, this message translates to:
  /// **'Crash data — specialist service required'**
  String get ctx_crash_data_specialist;

  /// No description provided for @ctx_comm_failed.
  ///
  /// In en, this message translates to:
  /// **'Communication failed'**
  String get ctx_comm_failed;

  /// No description provided for @ctx_cleared_and_verified.
  ///
  /// In en, this message translates to:
  /// **'Cleared and verified'**
  String get ctx_cleared_and_verified;

  /// No description provided for @reason_not_connected.
  ///
  /// In en, this message translates to:
  /// **'Connect to the car first.'**
  String get reason_not_connected;

  /// No description provided for @reason_replay.
  ///
  /// In en, this message translates to:
  /// **'A replay is not a car — nothing can be cleared.'**
  String get reason_replay;

  /// No description provided for @reason_module_not_read.
  ///
  /// In en, this message translates to:
  /// **'The module did not answer, so its codes are unknown.'**
  String get reason_module_not_read;

  /// No description provided for @reason_module_refused.
  ///
  /// In en, this message translates to:
  /// **'The module refused access (e.g. security gateway).'**
  String get reason_module_refused;

  /// No description provided for @reason_address_unverified.
  ///
  /// In en, this message translates to:
  /// **'Its address has not been verified on a real car yet.'**
  String get reason_address_unverified;

  /// No description provided for @reason_clear_not_documented.
  ///
  /// In en, this message translates to:
  /// **'No documented clear function for this module.'**
  String get reason_clear_not_documented;

  /// No description provided for @reason_adapter_no_headers.
  ///
  /// In en, this message translates to:
  /// **'This adapter failed the header test needed to address the module.'**
  String get reason_adapter_no_headers;

  /// No description provided for @reason_active_fault.
  ///
  /// In en, this message translates to:
  /// **'The fault is active now — clearing would not help and could hide it. Repair first.'**
  String get reason_active_fault;

  /// No description provided for @reason_crash_data.
  ///
  /// In en, this message translates to:
  /// **'Crash/deployment data is never cleared here — see an airbag specialist.'**
  String get reason_crash_data;

  /// No description provided for @reason_safety_policy.
  ///
  /// In en, this message translates to:
  /// **'Safety system: clearing must be allowed for this car on the server first.'**
  String get reason_safety_policy;

  /// No description provided for @res_cleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get res_cleared;

  /// No description provided for @res_still_active.
  ///
  /// In en, this message translates to:
  /// **'Still present'**
  String get res_still_active;

  /// No description provided for @res_read_failed.
  ///
  /// In en, this message translates to:
  /// **'Re-read failed'**
  String get res_read_failed;

  /// No description provided for @res_verification_pending.
  ///
  /// In en, this message translates to:
  /// **'Verification pending'**
  String get res_verification_pending;

  /// No description provided for @res_refused.
  ///
  /// In en, this message translates to:
  /// **'Refused by the module'**
  String get res_refused;

  /// No description provided for @res_comm_failed.
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get res_comm_failed;

  /// No description provided for @res_blocked.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get res_blocked;

  /// No description provided for @kbOemUnknown.
  ///
  /// In en, this message translates to:
  /// **'Manufacturer-specific code: its meaning depends on the make{make} and is not in the local database. Check the manufacturer\'s service information.'**
  String kbOemUnknown(String make);

  /// No description provided for @detectedMake.
  ///
  /// In en, this message translates to:
  /// **'Make (from VIN): {make}'**
  String detectedMake(String make);

  /// No description provided for @indicatorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Warning lamps'**
  String get indicatorsTitle;

  /// No description provided for @indicatorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What the car\'s computers report for each dashboard lamp'**
  String get indicatorsSubtitle;

  /// No description provided for @indicatorsIntro.
  ///
  /// In en, this message translates to:
  /// **'What the car\'s computers report for each warning lamp. The app only reads states — it never switches dashboard lamps on or off. The lamp you see on the dashboard is the final word.'**
  String get indicatorsIntro;

  /// No description provided for @indicatorsCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get indicatorsCheckNow;

  /// No description provided for @indicatorsNoScan.
  ///
  /// In en, this message translates to:
  /// **'Run a full scan to read the airbag and ABS modules.'**
  String get indicatorsNoScan;

  /// No description provided for @indicatorsClearCta.
  ///
  /// In en, this message translates to:
  /// **'Clear options'**
  String get indicatorsClearCta;

  /// No description provided for @ind_engine.
  ///
  /// In en, this message translates to:
  /// **'Engine (Check Engine)'**
  String get ind_engine;

  /// No description provided for @ind_airbag.
  ///
  /// In en, this message translates to:
  /// **'Airbag (SRS)'**
  String get ind_airbag;

  /// No description provided for @ind_abs.
  ///
  /// In en, this message translates to:
  /// **'ABS'**
  String get ind_abs;

  /// No description provided for @ind_battery.
  ///
  /// In en, this message translates to:
  /// **'Battery / charging'**
  String get ind_battery;

  /// No description provided for @ind_coolant.
  ///
  /// In en, this message translates to:
  /// **'Engine temperature'**
  String get ind_coolant;

  /// No description provided for @ind_oil.
  ///
  /// In en, this message translates to:
  /// **'Oil pressure'**
  String get ind_oil;

  /// No description provided for @ind_tpms.
  ///
  /// In en, this message translates to:
  /// **'Tyre pressure (TPMS)'**
  String get ind_tpms;

  /// No description provided for @ind_esc.
  ///
  /// In en, this message translates to:
  /// **'Stability control (ESC)'**
  String get ind_esc;

  /// No description provided for @ind_eps.
  ///
  /// In en, this message translates to:
  /// **'Power steering (EPS)'**
  String get ind_eps;

  /// No description provided for @ind_seatbelt.
  ///
  /// In en, this message translates to:
  /// **'Seatbelt'**
  String get ind_seatbelt;

  /// No description provided for @indState_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get indState_ok;

  /// No description provided for @indState_fault.
  ///
  /// In en, this message translates to:
  /// **'Fault'**
  String get indState_fault;

  /// No description provided for @indState_warning.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get indState_warning;

  /// No description provided for @indState_unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get indState_unknown;

  /// No description provided for @indState_unsupported.
  ///
  /// In en, this message translates to:
  /// **'Not readable'**
  String get indState_unsupported;

  /// No description provided for @indState_checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get indState_checking;

  /// No description provided for @indSource_read.
  ///
  /// In en, this message translates to:
  /// **'read from the computer'**
  String get indSource_read;

  /// No description provided for @indSource_inferred.
  ///
  /// In en, this message translates to:
  /// **'inferred from module codes'**
  String get indSource_inferred;

  /// No description provided for @indDetail_mil_on.
  ///
  /// In en, this message translates to:
  /// **'The engine computer reports the lamp ON.'**
  String get indDetail_mil_on;

  /// No description provided for @indDetail_mil_off.
  ///
  /// In en, this message translates to:
  /// **'The engine computer reports the lamp OFF.'**
  String get indDetail_mil_off;

  /// No description provided for @indDetail_codes_stored.
  ///
  /// In en, this message translates to:
  /// **'The module has stored codes — its lamp is normally ON. (Inferred: the dashboard lamp itself can\'t be read.)'**
  String get indDetail_codes_stored;

  /// No description provided for @indDetail_module_no_codes.
  ///
  /// In en, this message translates to:
  /// **'The module answered with no codes. The lamp itself can\'t be read — after ignition ON it should go out within a few seconds.'**
  String get indDetail_module_no_codes;

  /// No description provided for @indDetail_module_not_read.
  ///
  /// In en, this message translates to:
  /// **'The module did not answer, so the state is unknown — not \"OK\". This adapter hasn\'t proven support for it.'**
  String get indDetail_module_not_read;

  /// No description provided for @indDetail_module_refused.
  ///
  /// In en, this message translates to:
  /// **'The module refused access, so the state is unknown.'**
  String get indDetail_module_refused;

  /// No description provided for @indDetail_charging_low.
  ///
  /// In en, this message translates to:
  /// **'Engine running but voltage is below 13 V — charging may be weak.'**
  String get indDetail_charging_low;

  /// No description provided for @indDetail_charging_ok.
  ///
  /// In en, this message translates to:
  /// **'Engine running, charging voltage normal.'**
  String get indDetail_charging_ok;

  /// No description provided for @indDetail_battery_low.
  ///
  /// In en, this message translates to:
  /// **'Engine off and battery below 12 V.'**
  String get indDetail_battery_low;

  /// No description provided for @indDetail_battery_ok_engine_off.
  ///
  /// In en, this message translates to:
  /// **'Engine off: the battery lamp is normally ON now — not a fault.'**
  String get indDetail_battery_ok_engine_off;

  /// No description provided for @indDetail_coolant_high.
  ///
  /// In en, this message translates to:
  /// **'Coolant at or above 110 °C.'**
  String get indDetail_coolant_high;

  /// No description provided for @indDetail_coolant_ok.
  ///
  /// In en, this message translates to:
  /// **'Coolant temperature normal.'**
  String get indDetail_coolant_ok;

  /// No description provided for @indDetail_no_data.
  ///
  /// In en, this message translates to:
  /// **'No reading yet — connect and tap \"Check now\".'**
  String get indDetail_no_data;

  /// No description provided for @indDetail_not_readable.
  ///
  /// In en, this message translates to:
  /// **'Not readable through generic OBD on this car (no verified module).'**
  String get indDetail_not_readable;

  /// No description provided for @kbOemUnverifiedTag.
  ///
  /// In en, this message translates to:
  /// **'community data, not verified by the manufacturer'**
  String get kbOemUnverifiedTag;

  /// No description provided for @kbArAiTag.
  ///
  /// In en, this message translates to:
  /// **'AI translation'**
  String get kbArAiTag;

  /// No description provided for @ecuMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Module map'**
  String get ecuMapTitle;

  /// No description provided for @ecuMapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every module tried in the last scan and how it answered'**
  String get ecuMapSubtitle;

  /// No description provided for @ecuMapNoScan.
  ///
  /// In en, this message translates to:
  /// **'Run a full scan to build the module map.'**
  String get ecuMapNoScan;

  /// No description provided for @ecu_discovered.
  ///
  /// In en, this message translates to:
  /// **'Discovered'**
  String get ecu_discovered;

  /// No description provided for @ecu_reachable.
  ///
  /// In en, this message translates to:
  /// **'Reachable'**
  String get ecu_reachable;

  /// No description provided for @ecu_dtc_read_supported.
  ///
  /// In en, this message translates to:
  /// **'Code read supported'**
  String get ecu_dtc_read_supported;

  /// No description provided for @ecu_clear_supported.
  ///
  /// In en, this message translates to:
  /// **'Clear supported'**
  String get ecu_clear_supported;

  /// No description provided for @ecu_not_supported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get ecu_not_supported;

  /// No description provided for @ecu_timed_out.
  ///
  /// In en, this message translates to:
  /// **'No answer (timed out)'**
  String get ecu_timed_out;

  /// No description provided for @ecu_gateway_blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked by security gateway'**
  String get ecu_gateway_blocked;

  /// No description provided for @ecu_refused.
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get ecu_refused;

  /// No description provided for @ecu_passed.
  ///
  /// In en, this message translates to:
  /// **'Read OK — no codes'**
  String get ecu_passed;

  /// No description provided for @ecu_faults_present.
  ///
  /// In en, this message translates to:
  /// **'Faults present'**
  String get ecu_faults_present;

  /// No description provided for @ecuAddrVerified.
  ///
  /// In en, this message translates to:
  /// **'address verified on a car'**
  String get ecuAddrVerified;

  /// No description provided for @ecuAddrUnverified.
  ///
  /// In en, this message translates to:
  /// **'address NOT verified'**
  String get ecuAddrUnverified;

  /// No description provided for @ecuSource.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String ecuSource(String source);

  /// No description provided for @ecuNrc.
  ///
  /// In en, this message translates to:
  /// **'Refused with NRC {nrc}'**
  String ecuNrc(String nrc);

  /// No description provided for @monitorTestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Self-test results (Mode 06)'**
  String get monitorTestsTitle;

  /// No description provided for @monitorTestsIntro.
  ///
  /// In en, this message translates to:
  /// **'Results of the engine computer\'s own monitor tests. A test passes when its value is within the limits the computer reports. Values are raw (unit code shown) — no units are guessed.'**
  String get monitorTestsIntro;

  /// No description provided for @monitorTestsRead.
  ///
  /// In en, this message translates to:
  /// **'Read results'**
  String get monitorTestsRead;

  /// No description provided for @monitorTestsNotCan.
  ///
  /// In en, this message translates to:
  /// **'Mode 06 is only decoded on CAN cars; this car\'s protocol uses a different format.'**
  String get monitorTestsNotCan;

  /// No description provided for @monitorTestsNotSupported.
  ///
  /// In en, this message translates to:
  /// **'The car did not report any Mode 06 tests.'**
  String get monitorTestsNotSupported;

  /// No description provided for @monitorTestsNeedConnection.
  ///
  /// In en, this message translates to:
  /// **'Connect to the car to read the results.'**
  String get monitorTestsNeedConnection;

  /// No description provided for @monitorTestsSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} tests · {failed} failed'**
  String monitorTestsSummary(int count, int failed);

  /// No description provided for @monitorPass.
  ///
  /// In en, this message translates to:
  /// **'PASS'**
  String get monitorPass;

  /// No description provided for @monitorFail.
  ///
  /// In en, this message translates to:
  /// **'FAIL'**
  String get monitorFail;

  /// No description provided for @monitorValues.
  ///
  /// In en, this message translates to:
  /// **'value {value} · limits {min} … {max} · UASID {uasid}'**
  String monitorValues(String value, String min, String max, String uasid);

  /// No description provided for @exportXlsx.
  ///
  /// In en, this message translates to:
  /// **'Export Excel (XLSX)'**
  String get exportXlsx;

  /// No description provided for @devConsoleTitle.
  ///
  /// In en, this message translates to:
  /// **'Developer diagnostics'**
  String get devConsoleTitle;

  /// No description provided for @devConsoleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live adapter traffic (TX/RX) and read-only commands'**
  String get devConsoleSubtitle;

  /// No description provided for @devConsoleIntro.
  ///
  /// In en, this message translates to:
  /// **'Every command and reply on the adapter link, live. You may send only read-only commands: adapter info (ATI, AT@1, ATRV, ATDP, ATDPN, ATCS, ATKW, ATIGN, ATPPS) and OBD read services 01, 02, 03, 06, 07, 09, 0A. Clearing, writing and adapter-changing commands are refused.'**
  String get devConsoleIntro;

  /// No description provided for @devConsoleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 0100 or ATRV'**
  String get devConsoleHint;

  /// No description provided for @devConsoleSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get devConsoleSend;

  /// No description provided for @devConsoleBlocked.
  ///
  /// In en, this message translates to:
  /// **'Refused: only read-only commands are allowed here.'**
  String get devConsoleBlocked;

  /// No description provided for @devConsoleExport.
  ///
  /// In en, this message translates to:
  /// **'Export log'**
  String get devConsoleExport;

  /// No description provided for @devConsoleClear.
  ///
  /// In en, this message translates to:
  /// **'Clear view'**
  String get devConsoleClear;

  /// No description provided for @devConsoleNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Connect to an adapter to see live traffic.'**
  String get devConsoleNotConnected;

  /// No description provided for @saveSessionFolder.
  ///
  /// In en, this message translates to:
  /// **'Save session folder'**
  String get saveSessionFolder;

  /// No description provided for @sessionFolderSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved: {path}'**
  String sessionFolderSaved(String path);

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @historySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search code, VIN, module, make, date…'**
  String get historySearchHint;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get filterLive;

  /// No description provided for @filterDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get filterDemo;

  /// No description provided for @filterInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get filterInterrupted;

  /// No description provided for @filterImported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get filterImported;

  /// No description provided for @openSessionsFolder.
  ///
  /// In en, this message translates to:
  /// **'Open sessions folder'**
  String get openSessionsFolder;

  /// No description provided for @exportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get exportPdf;
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
