import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/detail_widgets.dart';

class CADetailScreen extends StatefulWidget {
  final ApiService apiService;
  final int especeId;
  const CADetailScreen({super.key, required this.apiService, required this.especeId});
  @override
  State<CADetailScreen> createState() => _CADetailScreenState();
}

class _CADetailScreenState extends State<CADetailScreen> {
  List<dynamic> data = [];
  bool isLoading = true;
  String? error;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final result = await widget.apiService.getCA(widget.especeId);
      if (!mounted) return;
      setState(() { data = result; isLoading = false; error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e.toString(); isLoading = false; });
    }
  }
  double _num(dynamic value) => (value as num?)?.toDouble() ?? 0;
  String _money(double value) => AppSettings.instance.formatMoney(value, decimals: 0);
  String _short(double value) => value >= 1000000 ? '${(value / 1000000).toStringAsFixed(1)}M' : value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}K' : value.toStringAsFixed(0);
  double get _chartMax {
    final maximum = [
      ...data.map((item) => _num(item['total_ca'])),
      ...data.map((item) => _num(item['investissement'])),
    ].fold<double>(0, (current, value) => current > value ? current : value);
    return maximum <= 0 ? 1 : maximum * 1.2;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) return Scaffold(appBar: AppBar(title: Text(context.tr('revenue'))), body: Center(child: Text(error!)));
    if (data.isEmpty) return Scaffold(appBar: AppBar(title: Text(context.tr('revenue'))), body: Center(child: Text(context.tr('no_data'))));
    final revenue = data.fold<double>(0, (sum, item) => sum + _num(item['total_ca']));
    final investment = data.fold<double>(0, (sum, item) => sum + _num(item['investissement']));
    final margin = revenue - investment;
    final rate = investment == 0 ? 0.0 : revenue / investment * 100;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('revenue'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: LayoutBuilder(builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
            GridView.count(
              crossAxisCount: constraints.maxWidth >= 760 ? 4 : 2,
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12,
              childAspectRatio: constraints.maxWidth < 430 ? 1.15 : 1.55,
              children: [
                DetailMetricCard(label: 'Chiffre d’affaires', value: _money(revenue), icon: Icons.trending_up, color: TerreEtOrColors.green),
                DetailMetricCard(label: 'Investissement', value: _money(investment), icon: Icons.savings_outlined, color: TerreEtOrColors.gold),
                DetailMetricCard(label: 'Écart', value: _money(margin), icon: Icons.account_balance_wallet_outlined, color: margin >= 0 ? TerreEtOrColors.teal : const Color(0xFFD85B4B)),
                DetailMetricCard(label: 'Taux de récupération', value: '${rate.toStringAsFixed(1)} %', icon: Icons.pie_chart_outline, color: const Color(0xFF3D7FA1)),
              ],
            ),
            const SizedBox(height: 14),
            DetailSection(title: 'Comparaison par lot', subtitle: 'Chiffre d’affaires et investissement pour chaque lot', child: SizedBox(
              height: 300,
              child: BarChart(BarChartData(
                maxY: _chartMax,
                alignment: BarChartAlignment.spaceAround,
                barGroups: List.generate(data.length, (i) => BarChartGroupData(x: i, barsSpace: 5, barRods: [
                  BarChartRodData(toY: _num(data[i]['total_ca']), width: 14, color: TerreEtOrColors.teal, borderRadius: BorderRadius.circular(5)),
                  BarChartRodData(toY: _num(data[i]['investissement']), width: 14, color: TerreEtOrColors.gold, borderRadius: BorderRadius.circular(5)),
                ])),
                borderData: FlBorderData(show: false), gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, _) => Text(_short(v), style: const TextStyle(fontSize: 10, color: TerreEtOrColors.muted)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, _) { final i=v.toInt(); if(i<0||i>=data.length)return const SizedBox(); return Padding(padding: const EdgeInsets.only(top: 8), child: Text(data[i]['nom']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))); })),
                ),
              )),
            )),
            const SizedBox(height: 12),
            const Wrap(spacing: 20, children: [_Legend('Chiffre d’affaires', TerreEtOrColors.teal), _Legend('Investissement', TerreEtOrColors.gold)]),
          ],
        )),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label; final Color color;
  const _Legend(this.label, this.color);
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 11,height: 11,decoration: BoxDecoration(color:color,borderRadius:BorderRadius.circular(3))),const SizedBox(width:6),Text(label)]);
}
