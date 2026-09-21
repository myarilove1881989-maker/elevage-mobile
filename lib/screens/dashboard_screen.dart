import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_elevage/screens/add_achat_screen.dart';
import 'package:app_elevage/screens/add_mouvement_screen.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/screens/lot_list_screen.dart';

import '../main.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;


import 'package:app_elevage/screens/stock_detail_screen.dart';
import 'package:app_elevage/screens/ca_detail_screen.dart';
import 'package:app_elevage/screens/depense_detail_screen.dart';
import 'package:app_elevage/screens/marge_detail_screen.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:app_elevage/screens/client_list_screen.dart';
import 'package:app_elevage/screens/dettes_screen.dart';
import 'package:app_elevage/screens/performance_screen.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/screens/settings_screen.dart';
import 'package:app_elevage/l10n/app_localizations.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardScreen extends StatefulWidget {
  final ApiService apiService;

  const DashboardScreen({
    super.key,
    required this.apiService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late ApiService apiService;

  Map<String, dynamic>? data;
  List lots = [];
  List especes = [];

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  List _createdSpecies(List allSpecies, List currentLots) {
    final createdIds = currentLots
        .map((lot) => _intValue(lot['espece']))
        .whereType<int>()
        .toSet();

    return allSpecies
        .where((species) => createdIds.contains(_intValue(species['id'])))
        .toList();
  }

  int? selectedLotId;
  int? selectedEspeceId;

  final ScrollController _tasksScrollController = ScrollController();

  bool isLoading = true;

  double totalDettes = 0;
  String username = '';

DateTime _focusedDay = DateTime.now();
DateTime? _selectedDay;

Map<String, List<Map<String, dynamic>>> events = {};

String getDateKey(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

  Future<void> loadUsername() async {
  final prefs = await SharedPreferences.getInstance();

  if (!mounted) return;

  setState(() {
    username = prefs.getString("username") ?? '';
  });
}

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("token");
    await prefs.remove("username");
    ApiService.token = null;
    globalToken = null;

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(apiService: apiService),
      ),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    print("?? INITSTATE CALLED");
    apiService = widget.apiService;
    loadUsername();
    initData();
}
  Future<void> testApi() async {
  try {
    final res = await apiService.getDashboard();
    print("? API OK");
    print(res);
  } catch (e) {
    print("? API ERROR: $e");
  }
}
  Future<void> loadTasks() async {
  final res = await apiService.getTasks();

  Map<String, List<Map<String, dynamic>>> temp = {};

  for (var task in res) {
    final rawDate = task["date"];
    final date = rawDate.split("T")[0];

    temp.putIfAbsent(date, () => []);
    temp[date]!.add(task); // ?? garde tout (id + title)
  }
  print(temp);
  

  setState(() {
    events = temp;
    
  });
}

  Future<void> initData() async {
  try {
    print("?? INIT START");

    final results = await Future.wait([
      widget.apiService.getDashboard(),
      widget.apiService.getLots(),
      widget.apiService.getEspeces(),
      widget.apiService.getTasks(),
      widget.apiService.getTotalDettes(),
    ]);

    if (!mounted) return;

    setState(() {
      data = results[0] as Map<String, dynamic>;
      lots = results[1] as List;
      especes = _createdSpecies(results[2] as List, lots);
    
      // ?? tasks
      final rawTasks = results[3] as List;
      Map<String, List<Map<String, dynamic>>> temp = {};
      for (var task in rawTasks) {
        final date = task["date"].split("T")[0];
        temp.putIfAbsent(date, () => []);
        temp[date]!.add(task);
      }
      events = temp;

      totalDettes = (results[4] as double);

      isLoading = false;
    });

  } catch (e) {
    print("? ERREUR INIT: $e");

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Erreur: $e")),
    );
  }
}

  Future<void> fetchDashboard() async {
  try {
    final result = await widget.apiService.getDashboard();

    if (!mounted) return;

    setState(() {
      data = result;
    });

  } catch (e) {
    print("? dashboard error: $e");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Erreur dashboard")),
    );
  }
}

  Future<void> fetchDashboardByEspece(int? especeId) async {
    try {
      setState(() => isLoading = true);

      final result =
          await widget.apiService.getDashboard(especeId: especeId);

      if (!mounted) return;

      setState(() {
        data = result;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Erreur chargement des données de l'espèce"),
        ),
      );
    }
  }

  Future<void> fetchLots() async {
  try {
    final result = await widget.apiService.getLots();

    if (!mounted) return;

    setState(() {
      lots = result;
    });
  } catch (e) {
    print("? lots error: $e");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Erreur chargement lots")),
    );
  }
}

  Future<void> fetchEspeces() async {
  try {
    final result = await widget.apiService.getEspeces();

    if (!mounted) return;

    setState(() {
      especes = _createdSpecies(result, lots);

      if (selectedEspeceId != null &&
          !especes.any((species) =>
              _intValue(species['id']) == selectedEspeceId)) {
        selectedEspeceId = null;
        selectedLotId = null;
      }
    });
  } catch (e) {
    print("? especes error: $e");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Erreur chargement espèces")),
    );
  }
}

  Future<void> fetchLotDetail(int lotId) async {
  try {
    setState(() => isLoading = true);

    final result = await widget.apiService.getLotDetail(lotId);

    if (!mounted) return;

    setState(() {
      data = result;
      isLoading = false;
    });
  } catch (e) {
    print("? lot detail error: $e");

    if (!mounted) return;

    setState(() => isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Erreur chargement lot")),
    );
  }
}

  Future<void> scheduleNotification(String title, DateTime date) async {
  final scheduledDate = tz.TZDateTime.from(
    DateTime(date.year, date.month, date.day, 8),
    tz.local,
  );

  await notificationsPlugin.zonedSchedule(
    0,
    "Tâche du jour",
    title,
    scheduledDate,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'tasks',
        'Tasks',
        importance: Importance.max,
        priority: Priority.high,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.dateAndTime,
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
  );
}
  Widget buildCard(
    String title,
    dynamic value,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    bool isMoney = false,
    String? unit,
  }) {
    final subtitle =
        unit ?? (isMoney ? AppSettings.instance.currency.symbol : '');

  return Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
    elevation: 0,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFE4E8EC),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 34,
                      color: color,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    isMoney
                        ? AppSettings.instance.formatMoney(value).replaceAll(
                              AppSettings.instance.currency.symbol,
                              '',
                            ).trim()
                        : value.toString(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),

                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF607080),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Trait coloré en bas de la card
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  List getFilteredLots() {
    if (selectedEspeceId == null) return lots;

    return lots.where((lot) {
      return _intValue(lot["espece"]) == selectedEspeceId;
    }).toList();
  }

List<Map<String, dynamic>> _getTasksForDay() {
  final day = _selectedDay ?? DateTime.now();
  final key = getDateKey(day);

  return events[key] ?? [];
}
  

  Future<void> refreshDashboard() async {
  if (selectedLotId != null) {
    await fetchLotDetail(selectedLotId!);
  } else if (selectedEspeceId != null) {
    await fetchDashboardByEspece(selectedEspeceId);
  } else {
    // ? CAS GLOBAL (IMPORTANT)
    await fetchDashboard();
  }

  await fetchLots();
  await fetchEspeces();

  final dettes = await apiService.getTotalDettes();

  setState(() {
    totalDettes = dettes;
  });
}

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text("choisis d'abord une espèce ou lot")),
);
  }
  void _showTasksForDay(DateTime day) {
  final key = getDateKey(day);
  final tasks = events[key] ?? [];

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text("${context.tr('today_tasks')} ${day.day}/${day.month}"),
      content: tasks.isEmpty
          ? Text(context.tr('no_task'))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: tasks
                  .map((t) => ListTile(
  leading: const Icon(Icons.check_circle, color: Colors.green),
  title: Text(t["title"]),

  // ?? BOUTON SUPPRIMER
  trailing: IconButton(
    icon: const Icon(Icons.delete, color: Colors.red),
    onPressed: () async {
      await apiService.deleteTask(t["id"]);
      await loadTasks();

      if (mounted && Navigator.canPop(context)) {
    Navigator.pop(context);
  } // ferme popup

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('task_deleted'))),
      );
    },
  ),
))
                  .toList(),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('close')),
        )
      ],
    ),
  );
}
void _addTask() {
  String newTask = "";

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(context.tr('new_task')),
      content: TextField(
        onChanged: (value) => newTask = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: () async {
            final day = _selectedDay ?? DateTime.now();

            await apiService.createTask(newTask, day);

            try {
                await scheduleNotification(newTask, day);
                } catch (e) {
                print(e);
              }

        Navigator.pop(context);
            await loadTasks();
          },
          child: Text(context.tr('add')),
        ),
      ],
    ),
  );
}

  Future<void> _refreshAll() async {
    setState(() => isLoading = true);
    await refreshDashboard();
    await fetchEspeces();
    await loadTasks();
    if (!mounted) return;
    setState(() => isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('data_updated'))),
    );
  }

  Future<void> _openLots() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LotListScreen(apiService: apiService)),
    );
    if (result == true) await refreshDashboard();
  }

  Future<void> _openDepense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddDepenseScreen(apiService: apiService)),
    );
    if (result == true) await refreshDashboard();
  }

  Future<void> _openMouvement() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddMouvementScreen(apiService: apiService)),
    );
    if (result == true) await refreshDashboard();
  }

  Future<void> _openAchat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddAchatScreen(apiService: apiService)),
    );
    if (result == true) await refreshDashboard();
  }

  void _openClients() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClientListScreen(apiService: apiService)),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openTutorial() async {
    final tutorialUrl = Uri.parse(
      'https://elevage-mobile.onrender.com/guide-utilisateur-elevage.pdf',
    );

    final opened = await launchUrl(
      tutorialUrl,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tutorial_open_error'))),
      );
    }
  }

  Widget _brandTitle() {
    return RichText(
      text: const TextSpan(
        children: [
          TextSpan(
            text: "Elev'",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          TextSpan(
            text: "Age",
            style: TextStyle(
              color: Color(0xFF4CAF50),
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigationDrawer() {
    Widget item(String label, IconData icon, VoidCallback action) {
      return ListTile(
        leading: Icon(icon, color: const Color(0xFF063B63)),
        title: Text(label),
        onTap: () {
          Navigator.pop(context);
          action();
        },
      );
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFF063B63),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: _brandTitle(),
            ),
            item(context.tr('purchases'), Icons.shopping_bag_outlined, () => _openAchat()),
            item(context.tr('expenses'), Icons.shopping_cart_outlined, () => _openDepense()),
            item(
              context.tr('movements'),
              Icons.swap_horiz,
              () => _openMouvement(),
            ),
            item(context.tr('billing'), Icons.receipt_long_outlined, _openClients),
            item(context.tr('history'), Icons.history, () => _openLots()),
            item(context.tr('settings'), Icons.settings_outlined, _openSettings),
            item(context.tr('tutorial'), Icons.menu_book_outlined, _openTutorial),
            const Spacer(),
            const Divider(height: 1),
            item(context.tr('logout'), Icons.logout, _logout),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tasksScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
  return Scaffold(
    appBar: AppBar(
  backgroundColor: const Color(0xFF063B63),
  foregroundColor: Colors.white,
  elevation: 0,
  title: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 3,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            width: 22,
            height: 3,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            width: 22,
            height: 3,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
      const SizedBox(width: 16),
      RichText(
        text: const TextSpan(
          children: [
            TextSpan(
              text: "Elev'",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            TextSpan(
              text: "Age",
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
),
    body: const Center(
      child: CircularProgressIndicator(),
    ),
  );
}

    final kpis = data?["kpis"] ?? {};
    final filteredLots = getFilteredLots();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showNavActions = screenWidth >= 1100;

    return Scaffold(
      drawer: _navigationDrawer(),
      appBar: AppBar(
  automaticallyImplyLeading: false,
  backgroundColor: const Color(0xFF063B63),
  foregroundColor: Colors.white,
  elevation: 0,
          toolbarHeight: 76,

        title: Row(
          children: [

            // =========================
            // LOGO ELEV'AGE
            // =========================
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (menuContext) => IconButton(
                    tooltip: context.tr('open_menu'),
                    icon: const Icon(Icons.menu, size: 30),
                    onPressed: () => Scaffold.of(menuContext).openDrawer(),
                  ),
                ),

                const SizedBox(width: 6),

                RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: "Elev'",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                      TextSpan(
                        text: "Age",
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Espace entre le logo et les boutons
            const SizedBox(width: 8),

            // =========================
            // NAVIGATION
            // =========================
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [

                  // ACTUALISER
                  InkWell(
                    onTap: _refreshAll,
                    child: SizedBox(
                      width: screenWidth < 700 ? 44 : 76,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.refresh,
                            color: Colors.white,
                            size: 27,
                          ),
                          if (screenWidth >= 700) ...[
                            const SizedBox(height: 2),
                            Text(
                              context.tr('refresh'),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  if (showNavActions) ...[
                  const SizedBox(width: 8),

                  // ACHATS
                  InkWell(
                    onTap: _openAchat,
                    child: SizedBox(
                      width: 80,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            color: Colors.white,
                            size: 30,
                          ),
                          SizedBox(height: 3),
                          Text(
                            context.tr('purchases'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 18),

                  // DÉPENSES
                  InkWell(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AddDepenseScreen(apiService: apiService),
                        ),
                      );

                      if (result == true) {
                        await refreshDashboard();
                      }
                    },
                    child: SizedBox(
                      width: 90,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            color: Colors.white,
                            size: 30,
                          ),
                          SizedBox(height: 3),
                          Text(
                            context.tr('expenses'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 18),

                  // MOUVEMENTS
                  InkWell(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AddMouvementScreen(apiService: apiService),
                        ),
                      );

                      if (result == true) {
                        await refreshDashboard();
                      }
                    },
                    child: SizedBox(
                      width: 105,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.swap_horiz,
                            color: Colors.white,
                            size: 30,
                          ),
                          SizedBox(height: 3),
                          Text(
                            context.tr('movements'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 18),

                  // FACTURATION
                  InkWell(
                    onTap: _openClients,
                    child: SizedBox(
                      width: 92,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            color: Colors.white,
                            size: 30,
                          ),
                          SizedBox(height: 3),
                          Text(
                            context.tr('billing'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 18),
                  
                  // HISTORIQUE
                  InkWell(
                    onTap: _openLots,
                    child: SizedBox(
                      width: 80,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            color: Colors.white,
                            size: 30,
                          ),
                          SizedBox(height: 3),
                          Text(
                            context.tr('history'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  ],

                  const SizedBox(width: 4),

                  // DÉCONNEXION
                  InkWell(
                    onTap: _logout,
                    child: SizedBox(
                      width: screenWidth < 700 ? 44 : 64,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.logout,
                            color: Colors.white70,
                            size: 25,
                          ),
                          if (screenWidth >= 700) ...[
                            const SizedBox(height: 2),
                            Text(
                              context.tr('logout'),
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
        
      body: SingleChildScrollView(
        child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
              /// ?? TITRE SECTION (remplace AppBar subtitle)
Padding(
  padding: const EdgeInsets.only(
    top: 28,
    bottom: 22,
  ),
  child: Column(
    children: [
      RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text: context.tr('dashboard'),
              style: const TextStyle(
                color: Color(0xFF063B63),
                fontSize: 42,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (username.isNotEmpty)
              TextSpan(
                text: " $username",
                style: const TextStyle(
                  color: Color(0xFF16834B),
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),

      const SizedBox(height: 4),

      Text(
        context.tr('overview'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF607080),
          fontSize: 22,
          fontWeight: FontWeight.w400,
        ),
      ),
    ],
  ),
),
LayoutBuilder(
  builder: (context, constraints) {
    final bool horizontal = constraints.maxWidth >= 700;

    Widget especeFilter() {
      return DropdownButtonFormField<int>(
        value: selectedEspeceId ?? 0,
        decoration: InputDecoration(
          labelText: context.tr('species'),
          prefixIcon: const Icon(
            Icons.pets,
            color: Colors.green,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFE0E6EA),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF0B4F7C),
              width: 1.5,
            ),
          ),
        ),
        items: [
          DropdownMenuItem<int>(
            value: 0,
            child: Text(context.tr('all_species')),
          ),
          ...especes.map<DropdownMenuItem<int>>((e) {
            return DropdownMenuItem<int>(
              value: _intValue(e["id"])!,
              child: Text(e["nom"].toString()),
            );
          }),
        ],
        onChanged: (value) {
          setState(() {
            selectedEspeceId = value == 0 ? null : value;
            selectedLotId = null;
          });

          fetchDashboardByEspece(
            value == 0 ? null : value,
          );
        },
      );
    }

    Widget lotFilter() {
      return DropdownButtonFormField<int?>(
        value: selectedLotId,
        decoration: InputDecoration(
          labelText: context.tr('batch'),
          prefixIcon: const Icon(
            Icons.inventory_2_outlined,
            color: Color(0xFF0B4F7C),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFE0E6EA),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF0B4F7C),
              width: 1.5,
            ),
          ),
        ),
        items: [
          DropdownMenuItem<int?>(
            value: null,
            child: Text(context.tr('all_lots')),
          ),
          ...filteredLots.map((lot) {
            return DropdownMenuItem<int?>(
              value: lot["id"],
              child: Text(lot["nom"].toString()),
            );
          }),
        ],
        onChanged: (value) {
          setState(() {
            selectedLotId = value;
          });

          if (value == null) {
            fetchDashboardByEspece(selectedEspeceId);
          } else {
            fetchLotDetail(value);
          }
        },
      );
    }

    if (horizontal) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        width: 430,
        child: especeFilter(),
      ),
      const SizedBox(width: 32),
      SizedBox(
        width: 430,
        child: lotFilter(),
      ),
    ],
  );
}

    return Column(
      children: [
        especeFilter(),
        const SizedBox(height: 10),
        lotFilter(),
      ],
    );
  },
),

const SizedBox(height: 22),

              LayoutBuilder(
  builder: (context, constraints) {
    int columns;
double cardRatio;

if (constraints.maxWidth >= 1400) {
  // Grand écran : 5 cards sur une ligne
  columns = 5;
  cardRatio = 1.55;
} else if (constraints.maxWidth >= 1100) {
  // écran moyen : 5 cards sur une ligne
  columns = 5;
  cardRatio = 1.45;
} else if (constraints.maxWidth >= 800) {
  // écran réduit : 3 cards par ligne
  columns = 3;
  cardRatio = 1.50;
} else if (constraints.maxWidth >= 550) {
  // Tablette : 2 cards par ligne
  columns = 2;
  cardRatio = 1.55;
} else {
  // Téléphone : 1 card par ligne
  columns = 1;
  cardRatio = 1.70;
}

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: cardRatio,
      children: [
        buildCard(
          context.tr('stock_total'),
          kpis["stock"] ?? kpis["stock_total"] ?? 0,
          Icons.inventory_2,
          Colors.green,
          () {
            if (selectedLotId == null) {
              showError(context.tr('choose_lot'));
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StockDetailScreen(
                  apiService: apiService,
                  lotId: selectedLotId!,
                ),
              ),
            );
          },
          unit: context.tr('units'),
        ),

        buildCard(
          context.tr('revenue'),
          kpis["chiffre_affaires"] ?? 0,
          Icons.trending_up,
          Colors.blue,
          () {
            if (selectedEspeceId == null) {
              showError(context.tr('species_required'));
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CADetailScreen(
                  apiService: apiService,
                  especeId: selectedEspeceId!,
                ),
              ),
            );
          },
          isMoney: true,
        ),

        buildCard(
          context.tr('expenses'),
          kpis["depenses"] ?? 0,
          Icons.account_balance_wallet,
          Colors.orange,
          () {
            if (selectedLotId == null) {
              showError(context.tr('choose_lot'));
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DepenseDetailScreenX(
                  apiService: apiService,
                  lotId: selectedLotId!,
                ),
              ),
            );
          },
          isMoney: true,
        ),

        buildCard(
          context.tr('performance'),
          kpis["performance"] ?? 0,
          Icons.pie_chart,
          Colors.deepPurple,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PerformanceScreen(
                  apiService: apiService,
                ),
              ),
            );
          },
          unit: context.tr('margin_revenue'),
        ),

        buildCard(
          context.tr('client_balance'),
          totalDettes,
          Icons.credit_card,
          Colors.teal,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DettesScreen(
                  apiService: apiService,
                ),
              ),
            );
          },
          isMoney: true,
        ),
      ],
    );
  },
),

const SizedBox(height: 40),


LayoutBuilder(
  builder: (context, constraints) {
    final bool isLargeScreen = constraints.maxWidth >= 900;

    // ================= CALENDRIER =================
    Widget calendarCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month,
                color: Color(0xFF0B4F7C),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('task_calendar'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0B4F7C),
                ),
              ),
              const Spacer(),
              if (isLargeScreen)
                ElevatedButton.icon(
                  onPressed: _addTask,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.tr('add')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8F5E9),
                    foregroundColor: const Color(0xFF168A45),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 6),

          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,

            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },

            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });

              final key = getDateKey(selectedDay);
              final tasks = events[key] ?? [];

              if (tasks.isNotEmpty) {
                _showTasksForDay(selectedDay);
              }
            },

            eventLoader: (day) {
              final key = getDateKey(day);
              return events[key] ?? [];
            },

            daysOfWeekHeight: 20,
            rowHeight: 30,

            calendarStyle: CalendarStyle(
              outsideDaysVisible: true,

              defaultTextStyle: const TextStyle(
                fontSize: 12,
                color: Color(0xFF455A64),
              ),

              weekendTextStyle: const TextStyle(
                fontSize: 12,
                color: Color(0xFF607D8B),
              ),

              outsideTextStyle: const TextStyle(
                fontSize: 11,
                color: Color(0xFFB0BEC5),
              ),

              todayDecoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),

              todayTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),

              selectedDecoration: const BoxDecoration(
                color: Color(0xFF0B4F7C),
                shape: BoxShape.circle,
              ),

              selectedTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),

              markersMaxCount: 1,

              markerDecoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),

              markerSize: 4,
              markerMargin: const EdgeInsets.only(top: 1),

              cellMargin: const EdgeInsets.all(3),
            ),

            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,

              leftChevronIcon: Icon(
                Icons.chevron_left,
                color: Color(0xFF0B4F7C),
              ),

              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: Color(0xFF0B4F7C),
              ),

              titleTextStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0B4F7C),
              ),

              headerPadding: EdgeInsets.symmetric(vertical: 2),
            ),

            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF78909C),
              ),

              weekendStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF78909C),
              ),
            ),
          ),
        ],
      ),
    );

    // ================= TÂCHES DU JOUR =================
final tasksForDay = _getTasksForDay();

Widget tasksCard = Container(
  height: double.infinity,
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    boxShadow: const [
      BoxShadow(
        color: Colors.black12,
        blurRadius: 8,
        offset: Offset(0, 3),
      ),
    ],
  ),
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ================= TITRE =================
      Row(
        children: [
          const Icon(
            Icons.calendar_today,
            color: Color(0xFF0B4F7C),
            size: 22,
          ),
          const SizedBox(width: 8),

          Text(
            context.tr('today_tasks'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0B4F7C),
            ),
          ),

          const Spacer(),

          // ================= NAVIGATION TÂCHES =================
          if (tasksForDay.length > 3) ...[
            IconButton(
              tooltip: context.tr('up'),
              icon: const Icon(
                Icons.keyboard_arrow_up,
                color: Color(0xFF0B4F7C),
              ),
              onPressed: () {
                if (!_tasksScrollController.hasClients) return;

                final current =
                    _tasksScrollController.offset;

                final target =
                    (current - 180).clamp(
                      0.0,
                      _tasksScrollController
                          .position
                          .maxScrollExtent,
                    );

                _tasksScrollController.animateTo(
                  target,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              },
            ),

            IconButton(
              tooltip: context.tr('down'),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Color(0xFF0B4F7C),
              ),
              onPressed: () {
                if (!_tasksScrollController.hasClients) return;

                final current =
                    _tasksScrollController.offset;

                final target =
                    (current + 180).clamp(
                      0.0,
                      _tasksScrollController
                          .position
                          .maxScrollExtent,
                    );

                _tasksScrollController.animateTo(
                  target,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              },
            ),
          ],

          // ================= AJOUT SUR PETIT ÉCRAN =================
          if (!isLargeScreen)
            IconButton(
              tooltip: context.tr('add_task'),
              onPressed: _addTask,
              icon: const Icon(
                Icons.add_circle,
                color: Color(0xFF168A45),
              ),
            ),
        ],
      ),

      const SizedBox(height: 8),

      // ================= CONTENU =================
      if (tasksForDay.isEmpty)
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE5EAF0),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.event_available,
                  size: 34,
                  color: Color(0xFF90A4AE),
                ),

                const SizedBox(height: 8),

                Text(
                  context.tr('no_task_planned'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF607D8B),
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  context.tr('free_day'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF90A4AE),
                  ),
                ),
              ],
            ),
          ),
        )
      else
        Expanded(
          child: ListView.builder(
            controller: _tasksScrollController,
            physics: const ClampingScrollPhysics(),
            itemCount: tasksForDay.length,
            itemBuilder: (context, index) {
              final task = tasksForDay[index];

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Dismissible(
                  key: Key(task["id"].toString()),
                  direction: DismissDirection.endToStart,

                  onDismissed: (_) async {
                    await apiService.deleteTask(task["id"]);
                    await loadTasks();

                    if (!mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Tâche supprimée"),
                      ),
                    );
                  },

                  background: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                    ),
                    child: const Icon(
                      Icons.delete,
                      color: Colors.white,
                    ),
                  ),

                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FBFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE3EAF0),
                      ),
                    ),

                    child: ListTile(
                      dense: true,

                      leading: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                      ),

                      title: Text(
                        task["title"],
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      trailing: IconButton(
                        tooltip: "Supprimer",
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 21,
                        ),

                        onPressed: () async {
                          await apiService.deleteTask(task["id"]);
                          await loadTasks();

                          if (!mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Tâche supprimée"),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ],
  ),
);

    // ================= DISPOSITION =================
if (isLargeScreen) {
  return SizedBox(
    height: 355,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: calendarCard,
        ),

        const SizedBox(width: 16),

        Expanded(
          child: tasksCard,
        ),
      ],
    ),
  );
}

    // ================= PETIT ÉCRAN =================
    return Column(
      children: [
        calendarCard,
        const SizedBox(height: 12),

        SizedBox(
          height: 310,
          child: tasksCard,
        ),
    ],
  );
  },
),
              ],
            ),
          ),
        ),
      );
  }
}





