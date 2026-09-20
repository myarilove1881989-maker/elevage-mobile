import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/services/app_settings.dart';

// 🔥 TIMEZONE (OBLIGATOIRE POUR NOTIFS)
import 'package:timezone/timezone.dart' as tz;
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
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.requestNotificationsPermission();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 OBLIGATOIRE POUR zonedSchedule
  tzdata.initializeTimeZones();

  // 🔔 init notifications
  await initNotifications();

  final apiService = ApiService();
  await apiService.loadToken();
  await AppSettings.instance.load();

  runApp(ElevageApp(apiService: apiService));
}

class ElevageApp extends StatelessWidget {
  final ApiService apiService;

  const ElevageApp({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        title: 'Élevage Mobile',
        debugShowCheckedModeBanner: false,
        locale: Locale(AppSettings.instance.languageCode),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          primarySwatch: Colors.green,
        ),
        home: LoginScreen(apiService: apiService),
      ),
    );
  }
}
