import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';

class CADetailScreen extends StatefulWidget {
  final ApiService apiService;
  final int especeId;

  const CADetailScreen({
    super.key,
    required this.apiService,
    required this.especeId,
  });

  @override
  State<CADetailScreen> createState() => _CADetailScreenState();
}

class _CADetailScreenState extends State<CADetailScreen> {
  List data = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.apiService.getCA(widget.especeId);

      print("DATA CA: $result"); // debug

      setState(() {
        data = result;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  // 🔥 FORMAT K
  String formatK(double value) {
    if (value >= 1000) {
      return "${(value / 1000).toStringAsFixed(0)}K";
    }
    return value.toStringAsFixed(0);
  }

  // 🔥 SAFE DOUBLE
  double toDouble(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return 0;
  }

  // ✅ GRAPH COMPARATIF
  List<BarChartGroupData> buildChartData() {
    if (data.isEmpty) return [];

    return List.generate(data.length, (i) {
      final item = data[i];

      final ca = toDouble(item["total_ca"]);
      final investissement = toDouble(item["investissement"]);

      return BarChartGroupData(
        x: i,
        barsSpace: 6,
        barRods: [
          // 🟠 INVESTISSEMENT
          BarChartRodData(
            toY: investissement,
            width: 10,
            borderRadius: BorderRadius.circular(4),
            color: Colors.orange,
          ),

          // 🔵 CA
          BarChartRodData(
            toY: ca,
            width: 10,
            borderRadius: BorderRadius.circular(4),
            color: Colors.blue,
          ),
        ],
      );
    });
  }

  // 🔹 Légende
  Widget legendItem(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(text),
      ],
    );
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
        appBar: AppBar(title: const Text("Erreur")),
        body: Center(child: Text(error!)),
      );
    }

    if (data.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("CA par lot")),
        body: const Center(child: Text("Aucune donnée")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("CA vs Investissement"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [

            // 🔥 LÉGENDE
            Row(
              children: [
                legendItem("Investissement", Colors.orange),
                const SizedBox(width: 16),
                legendItem("CA", Colors.blue),
              ],
            ),

            const SizedBox(height: 12),

            // ================= GRAPH =================
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  barGroups: buildChartData(),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            formatK(value),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();

                          if (index < 0 || index >= data.length) {
                            return const SizedBox();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              data[index]["nom"] ?? "",
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ================= LIST =================
            Expanded(
              child: ListView.builder(
                itemCount: data.length,
                itemBuilder: (_, i) {
                  final item = data[i];

                  final ca = toDouble(item["total_ca"]);
                  final investissement = toDouble(item["investissement"]);

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.show_chart, color: Colors.blue),
                      title: Text(item["nom"] ?? ""),
                      subtitle: Text(
                        "Investissement: ${formatK(investissement)}",
                        style: const TextStyle(color: Colors.orange),
                      ),
                      trailing: Text(
                        formatK(ca),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}