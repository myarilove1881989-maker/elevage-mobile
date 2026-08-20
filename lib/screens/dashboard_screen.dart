import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  int? selectedLotId;
  int? selectedEspeceId;

  bool isLoading = true;

  double totalDettes = 0;

DateTime _focusedDay = DateTime.now();
DateTime? _selectedDay;

Map<String, List<Map<String, dynamic>>> events = {};

String getDateKey(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

  @override
void initState() {
  super.initState();
  print("🔥 INITSTATE CALLED");
  apiService = widget.apiService;
  initData();
}
  Future<void> testApi() async {
  try {
    final res = await apiService.getDashboard();
    print("✅ API OK");
    print(res);
  } catch (e) {
    print("❌ API ERROR: $e");
  }
}
  Future<void> loadTasks() async {
  final res = await apiService.getTasks();

  Map<String, List<Map<String, dynamic>>> temp = {};

  for (var task in res) {
    final rawDate = task["date"];
    final date = rawDate.split("T")[0];

    temp.putIfAbsent(date, () => []);
    temp[date]!.add(task); // 🔥 garde tout (id + title)
  }
  print(temp);
  

  setState(() {
    events = temp;
    
  });
}

  Future<void> initData() async {
  try {
    print("🚀 INIT START");

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
      especes = results[2] as List;
    
      // 🔥 tasks
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
    print("❌ ERREUR INIT: $e");

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
    print("❌ dashboard error: $e");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Erreur dashboard")),
    );
  }
}

  Future<void> fetchDashboardByEspece(int? especeId) async {
    setState(() => isLoading = true);

    final result =
        await widget.apiService.getDashboard(especeId: especeId);

    if (!mounted) return;

    setState(() {
      data = result;
      isLoading = false;
    });
  }

  Future<void> fetchLots() async {
  try {
    final result = await widget.apiService.getLots();

    if (!mounted) return;

    setState(() {
      lots = result;
    });
  } catch (e) {
    print("❌ lots error: $e");

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
      especes = result;
    });
  } catch (e) {
    print("❌ especes error: $e");

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
    print("❌ lot detail error: $e");

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
  VoidCallback? onTap,
) {
  return Material(
    color: color.withOpacity(0.08),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // 🔥 centre vertical
          crossAxisAlignment: CrossAxisAlignment.center, // 🔥 centre horizontal
          children: [

            Icon(icon, size: 20, color: color),

            const SizedBox(height: 6),

            Text(
              value.toString(),
              textAlign: TextAlign.center, // 🔥 important
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 2),

            Text(
              title,
              textAlign: TextAlign.center, // 🔥 important
              style: const TextStyle(fontSize: 12),
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
      return lot["espece"] == selectedEspeceId;
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
    // ✅ CAS GLOBAL (IMPORTANT)
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
      title: Text("Tâches du ${day.day}/${day.month}"),
      content: tasks.isEmpty
          ? const Text("Aucune tâche")
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: tasks
                  .map((t) => ListTile(
  leading: const Icon(Icons.check_circle, color: Colors.green),
  title: Text(t["title"]),

  // 🔥 BOUTON SUPPRIMER
  trailing: IconButton(
    icon: const Icon(Icons.delete, color: Colors.red),
    onPressed: () async {
      await apiService.deleteTask(t["id"]);
      await loadTasks();

      if (mounted && Navigator.canPop(context)) {
    Navigator.pop(context);
  } // ferme popup

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tâche supprimée")),
      );
    },
  ),
))
                  .toList(),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Fermer"),
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
      title: const Text("Nouvelle tâche"),
      content: TextField(
        onChanged: (value) => newTask = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Annuler"),
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
          child: const Text("Ajouter"),
        ),
      ],
    ),
  );
}
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
  return Scaffold(
    appBar: AppBar(
      title: const Text("Elev'Age"),
    ),
    body: const Center(
      child: CircularProgressIndicator(),
    ),
  );
}

    final kpis = data?["kpis"] ?? {};
    final filteredLots = getFilteredLots();

    return Scaffold(
      appBar: AppBar(
  title: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: const [
      Text(
        "Elev'Age",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 30,
          color: Color.fromARGB(255, 51, 103, 81),
        ),
      ),
          ],
  ),
        actions: [

          IconButton(
  icon: const Icon(Icons.refresh),
  onPressed: () async {
    setState(() => isLoading = true);

    await refreshDashboard();
    await fetchEspeces();
    await loadTasks(); // 🔥 recharge tâches aussi

    setState(() => isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Données mises à jour")),
    );
  },
),
          // 📋 LISTE LOTS
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LotListScreen(apiService: apiService),
                ),
              );

              if (result == true) await refreshDashboard();
            },
          ),

          // 💰 DEPENSE
          IconButton(
            icon: const Icon(Icons.money),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddDepenseScreen(apiService: apiService),
                ),
              );

              if (result == true) await refreshDashboard();
            },
          ),

          // 🔄 MOUVEMENT
          IconButton(
            icon: const Icon(Icons.swap_vert),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddMouvementScreen(apiService: apiService),
                ),
              );

              if (result == true) await refreshDashboard();
            },
          ),

          // 🛒 ACHAT
          IconButton(
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddAchatScreen(apiService: apiService),
                ),
              );

              if (result == true) await refreshDashboard();
            },
          ),
          // 👥 CLIENTS 🔥
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () {
            Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClientListScreen(apiService: apiService),
                ),
                );
            },
          ),
        ],
     ),
        floatingActionButton: FloatingActionButton(
    onPressed: _addTask,
    child: const Icon(Icons.add),
  ),

      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              /// 🔥 TITRE SECTION (remplace AppBar subtitle)
Padding(
  padding: const EdgeInsets.only(bottom: 8, left: 4),
  child: Align(
    alignment: Alignment.center,
    child: Text(
      "Tableau de bord nom de l'élévage",
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.bold,
        color: Colors.orange,
      ),
    ),
  ),
),
DropdownButtonFormField<int>(
  value: selectedEspeceId ?? 0,
  decoration: const InputDecoration(
    border: InputBorder.none,
  ),
  items: [
    const DropdownMenuItem<int>(
      value: 0,
      child: Text("Toutes les espèces"),
    ),
    ...especes.map<DropdownMenuItem<int>>((e) {
      return DropdownMenuItem<int>(
        value: e["id"] as int,
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
),

              const SizedBox(height: 8),

              DropdownButtonFormField<int?>(
                value: selectedLotId,
                hint: const Text("Tous les lots"),
                items: [
                  const DropdownMenuItem(value: null, child: Text("Tous les lots")),
                  ...filteredLots.map((lot) {
                    return DropdownMenuItem(
                      value: lot["id"],
                      child: Text(lot["nom"]),
                    );
                  })
                ],
                onChanged: (value) {
                  setState(() => selectedLotId = value);

                  if (value == null) {
                    fetchDashboardByEspece(selectedEspeceId);
                  } else {
                    fetchLotDetail(value);
                  }
                },
              ),

              const SizedBox(height: 10),

              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.3,
                children: [

                  buildCard(
  "Stock",
  kpis["stock"] ?? kpis["stock_total"] ?? 0,
  Icons.storage,
  Colors.orange,
  () {
    if (selectedLotId == null) {
      showError("Choisis un lot");
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
),

                  buildCard("CA",
                      kpis["chiffre_affaires"] ?? 0,
                      Icons.attach_money, Colors.blue, () {
                    if (selectedEspeceId == null) {
                      showError("Choisis une espèce");
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
                  }),

                  buildCard("Dépenses",
                      kpis["depenses"] ?? 0,
                      Icons.money_off, Colors.red, () {
                    if (selectedLotId == null) {
                      showError("Choisis un lot");
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
                  }),

                  buildCard("Marge",
                      kpis["marge"] ?? 0,
                      Icons.trending_up,
                      (kpis["marge"] ?? 0) >= 0
                          ? Colors.green
                          : Colors.red, () {
                    if (selectedEspeceId == null) {
                      showError("Choisis une espèce");
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MargeDetailScreen(
                          apiService: apiService,
                          especeId: selectedEspeceId!,
                        ),
                      ),
                    );
                  }),
                
                buildCard( "Dettes",
  totalDettes,
  Icons.credit_card,
  Colors.purple,
  () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DettesScreen(apiService: apiService),
      ),
    );
  },
),

              buildCard(
  "Performance",
  "Classement",
  Icons.leaderboard,
  Colors.teal,
  () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PerformanceScreen(apiService: apiService),
      ),
    );
  },
),


                ],
              ),
              const SizedBox(height: 16),

Container(
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black12,
        blurRadius: 6,
        offset: Offset(0, 3),
      )
    ],
  ),
  padding: const EdgeInsets.all(10),
  child: TableCalendar(
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

  // 🔥 IMPORTANT : ICI
  eventLoader: (day) {
    final key = getDateKey(day);
    return events[key] ?? [];
  },

  calendarStyle: const CalendarStyle(
    markersMaxCount: 1, // 🔥 limite à 1 point
    markerDecoration: BoxDecoration(
      color: Colors.red,
      shape: BoxShape.circle,
    ),
  ),

  headerStyle: const HeaderStyle(
    formatButtonVisible: false,
    titleCentered: true,
  ),
),
),

const SizedBox(height: 10),

Align(
  alignment: Alignment.centerLeft,
  child: const Text(
    "Tâches du jour",
    style: TextStyle(fontWeight: FontWeight.bold),
  ),
),

const SizedBox(height: 6),

..._getTasksForDay().map((task) => Dismissible(
  key: Key(task["id"].toString()),
  direction: DismissDirection.endToStart,

  onDismissed: (_) async {
    await apiService.deleteTask(task["id"]);
    await loadTasks();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Tâche supprimée")),
    );
  },

  background: Container(
    color: Colors.red,
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: const Icon(Icons.delete, color: Colors.white),
  ),

  child: Card(
    child: ListTile(
      leading: const Icon(Icons.check_circle, color: Colors.green),
      title: Text(task["title"]),
      trailing: IconButton(
        icon: const Icon(Icons.delete, color: Colors.red),
        onPressed: () async {
          await apiService.deleteTask(task["id"]);
          await loadTasks();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Tâche supprimée")),
          );
        },
      ),
    ),
  ),
)),
            ],
          ),
        ),
      ),
    );
  }
}