import '../widgets/v2_components.dart';
import '../widgets/mutation_refresh.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/detail_widgets.dart';

class AquaticRevenueScreen extends StatefulWidget {
  final AquaticService service;
  final Map<String, String> filters;
  final VoidCallback? onHistory;

  const AquaticRevenueScreen({
    super.key,
    required this.service,
    required this.filters,
    this.onHistory,
  });
  @override
  State<AquaticRevenueScreen> createState() => _AquaticRevenueScreenState();
}

class _AquaticRevenueScreenState extends State<AquaticRevenueScreen>
    with MutationRefresh<AquaticRevenueScreen> {
  @override
  Future<void> refreshAfterMutation() async {
    await load();
  }

  List<dynamic> data = [];
  Object? billedRevenue;
  bool isLoading = true;
  int generation = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    markDataFresh();
    final epoch = ++generation, identity = ApiService.sessionIdentity;
    setState(() {
      isLoading = true;
      error = null;
      data = [];
    });
    try {
      final response = await widget.service.read(
        'finance-detail/?${Uri(queryParameters: widget.filters).query}',
      );
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity)
        return;
      final result = (response['cohorts'] as List)
          .map(
            (r) => {
              'nom': r['name'],
              'total_ca': r['revenue'],
              'investissement': r['investment'],
            },
          )
          .toList();
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity)
        return;
      setState(() {
        data = result;
        billedRevenue = response['billed_revenue'];
        isLoading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity)
        return;
      setState(() {
        error = 'Lecture impossible. Actualisez ou reconnectez-vous.';
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  double _num(dynamic value) => double.tryParse('$value') ?? 0;
  String _short(double value) => value >= 1000000
      ? '${(value / 1000000).toStringAsFixed(1)}M'
      : value >= 1000
      ? '${(value / 1000).toStringAsFixed(0)}K'
      : value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  double get _chartMax {
    final maximum = [
      ...data.map((item) => _num(item['total_ca'])),
      ...data.map((item) => _num(item['investissement'])),
    ].fold<double>(0, (current, value) => current > value ? current : value);
    return maximum <= 0 ? 1 : maximum * 1.2;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading)
      return V2Scaffold(
        appBar: V2AppBar(title: const Text('Chiffre d’affaires')),
        body: const Center(child: CircularProgressIndicator()),
      );
    if (error != null)
      return V2Scaffold(
        appBar: V2AppBar(title: Text(context.tr('revenue'))),
        body: Center(
          child: TextButton(onPressed: load, child: Text(error!)),
        ),
      );
    return V2Scaffold(
      appBar: V2AppBar(
        title: Text(context.tr('revenue')),
        actions: [
          if (widget.onHistory != null)
            IconButton(
              tooltip: 'Factures et historique',
              onPressed: widget.onHistory,
              icon: const Icon(Icons.receipt_long_outlined),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              GridView.count(
                crossAxisCount: constraints.maxWidth >= 1000 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: constraints.maxWidth < 430 ? 1.15 : 1.55,
                children: [
                  DetailMetricCard(
                    label: 'Chiffre d’affaires',
                    value: billedRevenue == null
                        ? '—'
                        : AppSettings.instance.formatMoney(
                            billedRevenue,
                            decimals: 0,
                          ),
                    icon: Icons.trending_up,
                    color: TerreEtOrColors.green,
                  ),
                  DetailMetricCard(
                    label: 'Investissement',
                    value: '—',
                    icon: Icons.savings_outlined,
                    color: TerreEtOrColors.gold,
                  ),
                  DetailMetricCard(
                    label: 'Écart',
                    value: '—',
                    icon: Icons.account_balance_wallet_outlined,
                    color: const Color(0xFFD85B4B),
                  ),
                  DetailMetricCard(
                    label: 'Taux de récupération',
                    value: '—',
                    icon: Icons.pie_chart_outline,
                    color: const Color(0xFF3D7FA1),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DetailSection(
                title: 'Comparaison par cohorte',
                subtitle:
                    'Chiffre d’affaires et investissement pour chaque cohorte',
                child: SizedBox(
                  height: 300,
                  child: BarChart(
                    BarChartData(
                      maxY: _chartMax,
                      alignment: BarChartAlignment.spaceAround,
                      barGroups: List.generate(
                        data.length,
                        (i) => BarChartGroupData(
                          x: i,
                          barsSpace: 5,
                          barRods: [
                            BarChartRodData(
                              toY: _num(data[i]['total_ca']),
                              width: 14,
                              color: TerreEtOrColors.teal,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            if (data[i]['investissement'] != null)
                              BarChartRodData(
                                toY: _num(data[i]['investissement']),
                                width: 14,
                                color: TerreEtOrColors.gold,
                                borderRadius: BorderRadius.circular(5),
                              ),
                          ],
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            getTitlesWidget: (v, _) => Text(
                              _short(v),
                              style: const TextStyle(
                                fontSize: 10,
                                color: TerreEtOrColors.muted,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= data.length)
                                return const SizedBox();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  data[i]['nom']?.toString() ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
              ),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 20,
                children: [
                  _Legend('Chiffre d’affaires', TerreEtOrColors.teal),
                  _Legend('Investissement', TerreEtOrColors.gold),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;
  const _Legend(this.label, this.color);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
