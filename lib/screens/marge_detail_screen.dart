import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../l10n/app_localizations.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';

class MargeDetailScreen extends StatefulWidget {
  final ApiService apiService;
  final int especeId;

  const MargeDetailScreen({
    super.key,
    required this.apiService,
    required this.especeId,
  });

  @override
  State<MargeDetailScreen> createState() => _MargeDetailScreenState();
}

class _MargeDetailScreenState extends State<MargeDetailScreen> {
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
      final result = await widget.apiService.getMarge(widget.especeId);

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

  List<BarChartGroupData> buildChartData() {
    return List.generate(data.length, (i) {
      final marge = (data[i]["marge"] ?? 0).toDouble();

      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: marge,
            width: 16,
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              colors: marge >= 0
                  ? [Colors.green.shade300, Colors.green]
                  : [Colors.red.shade300, Colors.red],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ],
      );
    });
  }

  double get totalMarge {
    return data.fold(0.0, (sum, e) => sum + (e["marge"] ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
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
        body: Center(child: Text(context.tr('no_data'))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(context.tr('margin')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ================= HEADER =================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    "Marge totale",
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppSettings.instance.formatMoney(totalMarge),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: totalMarge >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ================= GRAPH =================
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  barGroups: buildChartData(),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
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
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= data.length) {
                            return const SizedBox();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              data[index]["nom"] ?? "",
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                              ),
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
                  final marge = (item["marge"] ?? 0).toDouble();
                  final rentabilite =
                      (item["rentabilite"] ?? 0).toDouble();

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        // LEFT
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              item["nom"] ?? "",
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "${(rentabilite * 100).toStringAsFixed(1)} %",
                              style: TextStyle(
                                color: marge >= 0
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                        // RIGHT
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            Text(
                              AppSettings.instance.formatMoney(marge),
                              style: TextStyle(
                                color: marge >= 0
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Icon(
                              marge >= 0
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: marge >= 0
                                  ? Colors.green
                                  : Colors.red,
                              size: 14,
                            ),
                          ],
                        ),
                      ],
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
