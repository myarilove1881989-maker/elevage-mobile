
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'config.dart';
import 'services/lab_network_gate.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/services/app_settings.dart';

// 🔥 TIMEZONE (OBLIGATOIRE POUR NOTIFS)
import 'package:timezone/data/latest.dart' as tzdata;

// 🔔 NOTIFICATIONS
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');

  const settings = InitializationSettings(android: android);

  await notificationsPlugin.initialize(settings);

  // 🔥 Demande permission Android (sécurisé)
  final androidPlugin = notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  await androidPlugin?.requestNotificationsPermission();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Refuse before reading credentials or initializing any service.
  try {
    Config.current.validate(web: kIsWeb);
  } on StateError {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Configuration refusée. Le pilote exige son API autorisée.',
            ),
          ),
        ),
      ),
    );
    return;
  }

  // Only a reviewed, bounded approval compiled into a lab build can open it.
  if (Config.current.isLab) {
    await LabNetworkGate.instance.initializeFromBuild(Config.current);
  }

  // 🔥 OBLIGATOIRE POUR zonedSchedule
  tzdata.initializeTimeZones();

  // 🔔 init notifications
  try {
    if (!kIsWeb) await initNotifications();
  } on PlatformException {
    // Les rappels facultatifs ne doivent pas bloquer le démarrage.
  }

  final apiService = ApiService();
  var restoreFailed = false;
  final storedKind=(await SharedPreferences.getInstance()).getString('session_kind');
  // A remembered operator role is not an active session or a public route.
  const startFarmer=false;
  try {
    if(!startFarmer && storedKind=='owner') {
      await apiService.loadToken();
      if (kIsWeb && ApiService.token != null) {
        final caps = await apiService.get('/me/capabilities/');
        if (caps['role'] != 'OWNER') await apiService.logout();
      }
    }
  } on PlatformException {
    ApiService.token = null;
    globalToken = null;
    restoreFailed = true;
  } catch (_) {
    await apiService.logout();
    restoreFailed = true;
  }
  await AppSettings.instance.load();

  runApp(ElevageApp(apiService: apiService, restoreFailed: restoreFailed,startFarmer:startFarmer));
}

class ElevageApp extends StatefulWidget {
  final ApiService apiService;

  final bool restoreFailed;
  final bool startFarmer;
  const ElevageApp({
    super.key,
    required this.apiService,
    this.restoreFailed = false,
    this.startFarmer = false,
  });

  @override
  State<ElevageApp> createState() => _ElevageAppState();
}

class _ElevageAppState extends State<ElevageApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _redirectPending = false;

  @override
  void initState() {
    super.initState();
    ApiService.sessionExpired.addListener(_onSessionExpired);
  }

  @override
  void dispose() {
    ApiService.sessionExpired.removeListener(_onSessionExpired);
    super.dispose();
  }

  void _onSessionExpired() {
    if (_redirectPending || ApiService.farmerSession) return;
    _redirectPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              LoginScreen(apiService: widget.apiService, sessionExpired: true),
        ),
        (_) => false,
      );
      _redirectPending = false;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        title: Config.current.isLab
            ? 'Élev’Age LABORATOIRE'
            : Config.isPilot
            ? 'Élev’Age PILOTE'
            : 'Élev’Age',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        locale: Locale(AppSettings.instance.languageCode),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(primarySwatch: Colors.green),
        builder: (_, child) => SafeArea(
          top: false,
          child: Config.current.isLab
              ? Column(
                  children: [
                    const Material(
                      color: Colors.orange,
                      child: SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'LABORATOIRE — DONNÉES SYNTHÉTIQUES — réseau bloqué par défaut',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: child!),
                  ],
                )
              : Config.isPilot
              ? Column(
                  children: [
                    const Material(
                      color: Colors.orange,
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'PILOTE — DONNÉES FICTIVES',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: child!),
                  ],
                )
              : child!,
        ),
        home: !widget.startFarmer && ApiService.token != null
            ? DashboardScreen(apiService: widget.apiService)
            : LoginScreen(
                apiService: widget.apiService,
                restoreFailed: widget.restoreFailed,
              ),
      ),
    );
  }
}
