import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';

class PerformanceScreen extends StatefulWidget {
  final ApiService apiService;

  const PerformanceScreen({super.key, required this.apiService});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  static const speciesColors = <Color>[
    Color(0xFF279B68), Color(0xFFE4A13A), Color(0xFF167B77),
    Color(0xFF6C63B5), Color(0xFFD9676F), Color(0xFF3D86B6),
    Color(0xFF9A6A3A), Color(0xFF7A9E38), Color(0xFFC25B9A),
    Color(0xFF607D8B), Color(0xFFB7791F),
  ];

  List<Map<String, dynamic>> allRanking = [];
  List<Map<String, dynamic>> allMonthlySales = [];
  int selectedSpeciesId = 0;
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() { isLoading = true; error = null; });
    try {
      final result = await widget.apiService.getSpeciesPerformance();
      if (!mounted) return;
      setState(() {
        allRanking = (result['classement'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map)).toList();
        allMonthlySales = (result['ventes_mensuelles'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map)).toList();
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e.toString(); isLoading = false; });
    }
  }

  List<Map<String, dynamic>> get ranking => selectedSpeciesId == 0
      ? allRanking
      : allRanking.where((item) => item['espece_id'] == selectedSpeciesId).toList();

  List<Map<String, dynamic>> get monthlySales => selectedSpeciesId == 0
      ? allMonthlySales
      : allMonthlySales.where((item) => item['espece_id'] == selectedSpeciesId).toList();

  Color speciesColor(int id) => speciesColors[id.abs() % speciesColors.length];
  DateTime parseMonth(String value) => DateTime.parse('$value-01');

  String monthLabel(String? value, {bool short = false}) {
    if (value == null || value.isEmpty) return '—';
    return DateFormat(
      short ? 'MMM yy' : 'MMMM yyyy',
      AppSettings.instance.languageCode,
    ).format(parseMonth(value));
  }

  String money(dynamic value) {
    final amount = (value as num?)?.toDouble() ?? 0;
    return '${NumberFormat.decimalPattern('fr_FR').format(amount)} '
        '${AppSettings.instance.currency.symbol}';
  }

  List<String> get months {
    final values = monthlySales.map((item) => item['mois'].toString()).toSet().toList();
    values.sort();
    return values;
  }

  List<LineChartBarData> chartLines(List<String> chartMonths) {
    final species = <int>{
      for (final row in monthlySales) row['espece_id'] as int,
    };
    return species.map((id) {
      final quantities = <String, double>{};
      for (final row in monthlySales.where((item) => item['espece_id'] == id)) {
        quantities[row['mois'].toString()] = (row['quantite'] as num).toDouble();
      }
      final color = speciesColor(id);
      return LineChartBarData(
        spots: [
          for (var i = 0; i < chartMonths.length; i++)
            FlSpot(i.toDouble(), quantities[chartMonths[i]] ?? 0),
        ],
        isCurved: true,
        color: color,
        barWidth: 3,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
      );
    }).toList();
  }

  Widget buildRanking() => TerreEtOrPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('margin_ranking'), style: const TextStyle(
          color: TerreEtOrColors.ink, fontSize: 18, fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 14),
        if (ranking.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text(context.tr('no_data'))))
        else
          ...ranking.asMap().entries.map((entry) {
            final item = entry.value;
            final id = item['espece_id'] as int;
            final originalRank = allRanking.indexWhere((row) => row['espece_id'] == id) + 1;
            final rate = (item['taux_ecoulement'] as num).toDouble();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TerreEtOrColors.cream,
                borderRadius: BorderRadius.circular(14),
                border: Border(left: BorderSide(color: speciesColor(id), width: 5)),
              ),
              child: Row(children: [
                CircleAvatar(backgroundColor: speciesColor(id), foregroundColor: Colors.white,
                  child: Text('#$originalRank')),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['espece'].toString(), style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16,
                  )),
                  const SizedBox(height: 4),
                  Text('${context.tr('margin')}: ${money(item['marge'])}'),
                  Text('${context.tr('sell_through_rate')}: ${rate.toStringAsFixed(1)} %'),
                  Text(
                    '${context.tr('best_month')}: ${monthLabel(item['meilleur_mois']?.toString())} '
                    '· ${item['meilleur_mois_quantite'] ?? 0} ${context.tr('sold_units')}',
                    style: const TextStyle(color: TerreEtOrColors.muted),
                  ),
                ])),
              ]),
            );
          }),
      ],
    ),
  );

  Widget buildChart() {
    final chartMonths = months;
    return TerreEtOrPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('monthly_sales'), style: const TextStyle(
          color: TerreEtOrColors.ink, fontSize: 18, fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 8, children: ranking.map((item) {
          final id = item['espece_id'] as int;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(
              color: speciesColor(id), shape: BoxShape.circle,
            )),
            const SizedBox(width: 6),
            Text(item['espece'].toString()),
          ]);
        }).toList()),
        const SizedBox(height: 18),
        if (chartMonths.isEmpty)
          SizedBox(height: 260, child: Center(child: Text(context.tr('no_data'))))
        else
          SizedBox(height: 320, child: LineChart(LineChartData(
            minX: 0,
            maxX: chartMonths.length == 1
                ? 1
                : (chartMonths.length - 1).toDouble(),
            minY: 0,
            lineBarsData: chartLines(chartMonths),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => const FlLine(
                color: TerreEtOrColors.border, strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 42,
              )),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= chartMonths.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(monthLabel(chartMonths[index], short: true),
                      style: const TextStyle(fontSize: 11)),
                  );
                },
              )),
            ),
          ))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: terreEtOrTheme(context),
    child: Scaffold(
      appBar: AppBar(title: Text(context.tr('performance'))),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('${context.tr('error')}: $error'))
              : RefreshIndicator(
                  onRefresh: loadData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      TerreEtOrHeader(
                        icon: Icons.insights_outlined,
                        title: context.tr('performance'),
                        subtitle: AppSettings.instance.languageCode == 'en'
                            ? 'Compare margins and monthly sales by species'
                            : 'Comparez les marges et les ventes mensuelles par espèce',
                      ),
                      DropdownButtonFormField<int>(
                        value: selectedSpeciesId,
                        decoration: InputDecoration(
                          labelText: context.tr('species'),
                          prefixIcon: const Icon(Icons.pets_outlined),
                        ),
                        items: [
                          DropdownMenuItem<int>(value: 0,
                            child: Text(context.tr('all_species'))),
                          ...allRanking.map((item) => DropdownMenuItem<int>(
                            value: item['espece_id'] as int,
                            child: Text(item['espece'].toString()),
                          )),
                        ],
                        onChanged: (value) => setState(() => selectedSpeciesId = value),
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(builder: (context, constraints) {
                        if (constraints.maxWidth < 900) {
                          return Column(children: [
                            buildRanking(),
                            const SizedBox(height: 18),
                            buildChart(),
                          ]);
                        }
                        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: buildRanking()),
                          const SizedBox(width: 18),
                          Expanded(child: buildChart()),
                        ]);
                      }),
                    ],
                  ),
                ),
    ),
  );
}
