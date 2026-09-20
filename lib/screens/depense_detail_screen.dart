import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';

class DepenseDetailScreenX extends StatefulWidget {
  final ApiService apiService;
  final int lotId;

  const DepenseDetailScreenX({
    super.key,
    required this.apiService,
    required this.lotId,
  });

  @override
  State<DepenseDetailScreenX> createState() => _DepenseDetailScreenXState();
}

class _DepenseDetailScreenXState extends State<DepenseDetailScreenX> {
  List data = [];
  bool isLoading = true;
  String? error;

  double total = 0;

  // 🎨 COULEURS MÉTIER (MAJUSCULE pour éviter bug)
  final Map<String, Color> categoryColors = {
    "ALIMENT": Colors.green,
    "MEDICAMENT": Colors.blue,
    "TRANSPORT": Colors.brown,
    "ENTRETIEN": Colors.yellow,
    "SALAIRE": Colors.redAccent,
    "MAINTENANCE": Colors.grey,
    "AUTRE": Colors.grey,
  };

  // 🧠 ICÔNES MÉTIER
  final Map<String, IconData> categoryIcons = {
    "ALIMENT": Icons.agriculture,
    "MEDICAMENT": Icons.medical_services,
    "TRANSPORT": Icons.local_shipping,
    "ENTRETIEN": Icons.cleaning_services,
    "SALAIRE": Icons.attach_money,
    "MAINTENANCE": Icons.build,
    "AUTRE": Icons.category,
  };

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final res = await widget.apiService.getDepenses(widget.lotId);

      if (!mounted) return;

      double sum = 0;
      for (var item in res) {
        sum += (item["total"] ?? 0);
      }

      setState(() {
        data = res;
        total = sum;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  // 🔥 NORMALISATION NOM (clé du succès)
  String normalize(String? name) {
    if (name == null) return "AUTRE";
    return name.toUpperCase();
  }

  List<PieChartSectionData> buildSections() {
    return List.generate(data.length, (i) {
      final value = (data[i]["total"] ?? 0).toDouble();
      final percent = total == 0 ? 0 : (value / total * 100);

      final name = normalize(data[i]["categorie__nom"]);

      return PieChartSectionData(
        value: value,
        title: percent > 8 ? "${percent.toStringAsFixed(0)}%" : "",
        radius: 60,
        color: categoryColors[name] ?? Colors.grey,
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('error'))),
        body: Center(child: Text(error!)),
      );
    }

    if (data.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('expenses'))),
        body: Center(child: Text(context.tr('no_data'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${context.tr('expenses')} / ${context.tr('category')}'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [

              // ================= DONUT =================
              SizedBox(
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sections: buildSections(),
                        sectionsSpace: 4,
                        centerSpaceRadius: 55,
                      ),
                    ),

                    // 🔥 TOTAL CENTRE
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Total", style: TextStyle(fontSize: 12)),
                        Text(
                          total.toStringAsFixed(0),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ================= LISTE =================
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: data.length,
                itemBuilder: (_, i) {
                  final item = data[i];
                  final value = (item["total"] ?? 0).toDouble();
                  final percent =
                      total == 0 ? 0 : (value / total * 100);

                  final name = normalize(item["categorie__nom"]);

                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (categoryColors[name] ?? Colors.grey)
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          categoryIcons[name] ?? Icons.category,
                          color: categoryColors[name] ?? Colors.grey,
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle:
                          Text("${percent.toStringAsFixed(1)} % du total"),
                      trailing: Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
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
