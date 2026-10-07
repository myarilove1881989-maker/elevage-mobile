import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // 🔥 OBLIGATOIRE POUR zonedSchedule
  tzdata.initializeTimeZones();

  // 🔔 init notifications
  try {
    await initNotifications();
  } on PlatformException {
    // Les rappels facultatifs ne doivent pas bloquer le démarrage.
  }

  final apiService = ApiService();
  var restoreFailed = false;
  try {
    await apiService.loadToken();
  } on PlatformException {
    ApiService.token = null;
    globalToken = null;
    restoreFailed = true;
  }
  await AppSettings.instance.load();

  runApp(ElevageApp(apiService: apiService, restoreFailed: restoreFailed));
}

class ElevageApp extends StatefulWidget {
  final ApiService apiService;

  final bool restoreFailed;
  const ElevageApp({
    super.key,
    required this.apiService,
    this.restoreFailed = false,
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
    if (_redirectPending) return;
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
        title: 'Élev’Age',
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
        builder: (_, child) => SafeArea(top: false, child: child!),
        home: ApiService.token != null
            ? DashboardScreen(apiService: widget.apiService)
            : LoginScreen(
                apiService: widget.apiService,
                restoreFailed: widget.restoreFailed,
              ),
      ),
    );
  }
}
