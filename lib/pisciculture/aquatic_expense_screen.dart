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

class AquaticExpenseScreen extends StatefulWidget {
  final AquaticService service;
  final Map<String, String> filters;
  final VoidCallback? onHistory;

  final String? especeNom;
  final String? lotNom;
  const AquaticExpenseScreen({
    super.key,
    required this.service,
    required this.filters,
    this.onHistory,
    this.especeNom,
    this.lotNom,
  });
  @override
  State<AquaticExpenseScreen> createState() => _AquaticExpenseScreenState();
}

class _AquaticExpenseScreenState extends State<AquaticExpenseScreen>
    with MutationRefresh<AquaticExpenseScreen> {
  @override
  Future<void> refreshAfterMutation() async {
    await load();
  }

  List<dynamic> data = [];
  bool isLoading = true;
  int generation = 0;
  String? error;
  String? _especeNom;
  String? _lotNom;
  final colors = const [
    TerreEtOrColors.gold,
    Color(0xFFD85B4B),
    TerreEtOrColors.teal,
    Color(0xFF3D7FA1),
    Color(0xFF8A5A44),
    Color(0xFF7A6699),
  ];
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
      final result = (response['categories'] as List)
          .map((r) => {'categorie__nom': r['name'], 'total': r['amount']})
          .toList();
      result.sort((a, b) => _num(b['total']).compareTo(_num(a['total'])));
      setState(() {
        data = result;
        _especeNom = widget.especeNom;
        _lotNom = widget.lotNom;
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
  double get total =>
      data.fold<double>(0, (sum, item) => sum + _num(item['total']));
  String _name(dynamic item) => item['categorie__nom']?.toString() ?? 'Autre';
  String _money(double value) =>
      AppSettings.instance.formatMoney(value, decimals: 0);
  IconData _icon(String name) {
    final n = name.toUpperCase();
    if (n.contains('ALIMENT')) return Icons.grass;
    if (n.contains('MEDIC')) return Icons.medication_outlined;
    if (n.contains('TRANSPORT')) return Icons.local_shipping_outlined;
    if (n.contains('MAIN') || n.contains('SALAIRE'))
      return Icons.groups_outlined;
    if (n.contains('ENTRETIEN') || n.contains('MAINT'))
      return Icons.handyman_outlined;
    return Icons.category_outlined;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading)
      return V2Scaffold(
        appBar: V2AppBar(title: const Text('Dépenses / Catégorie')),
        body: const Center(child: CircularProgressIndicator()),
      );
    if (error != null)
      return V2Scaffold(
        appBar: V2AppBar(title: Text(context.tr('expenses'))),
        body: Center(
          child: TextButton(onPressed: load, child: Text(error!)),
        ),
      );
    final main = data.firstOrNull ?? {'categorie__nom': '—', 'total': 0};
    final mainValue = _num(main['total']);
    final selection = [
      _especeNom,
      _lotNom,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return V2Scaffold(
      appBar: V2AppBar(
        actions: [
          if (widget.onHistory != null)
            IconButton(
              tooltip: 'Historique et affectations',
              onPressed: widget.onHistory,
              icon: const Icon(Icons.history),
            ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${context.tr('expenses')} / ${context.tr('category')}'),
            if (selection.isNotEmpty)
              Text(
                selection,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            LayoutBuilder(
              builder: (context, c) => GridView.count(
                crossAxisCount: c.maxWidth >= 700 ? 2 : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: c.maxWidth >= 700 ? 2.5 : 2.8,
                children: [
                  DetailMetricCard(
                    label:
                        widget.filters.containsKey('cohort') ||
                            widget.lotNom != null
                        ? 'Dépenses de la cohorte'
                        : 'Dépenses piscicoles',
                    value: _money(total),
                    caption: '${data.length} catégories',
                    icon: Icons.account_balance_wallet_outlined,
                    color: const Color(0xFFD85B4B),
                  ),
                  DetailMetricCard(
                    label: 'Poste principal',
                    value: _name(main),
                    caption:
                        '${total == 0 ? 0 : (mainValue / total * 100).toStringAsFixed(0)} % · ${_money(mainValue)}',
                    icon: _icon(_name(main)),
                    color: TerreEtOrColors.gold,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            DetailSection(
              title: 'Répartition par catégorie',
              subtitle:
                  widget.filters.containsKey('cohort') || widget.lotNom != null
                  ? 'Dépenses de la cohorte préalablement sélectionnée'
                  : 'Dépenses du périmètre sélectionné',
              child: LayoutBuilder(
                builder: (context, c) {
                  final chart = SizedBox(
                    width: 210,
                    height: 210,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (total > 0)
                          PieChart(
                            PieChartData(
                              centerSpaceRadius: 58,
                              sectionsSpace: 3,
                              sections: List.generate(data.length, (i) {
                                final value = _num(data[i]['total']);
                                return PieChartSectionData(
                                  value: value,
                                  color: colors[i % colors.length],
                                  radius: 36,
                                  title: total == 0
                                      ? ''
                                      : '${(value / total * 100).toStringAsFixed(0)}%',
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }),
                            ),
                          ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                color: TerreEtOrColors.muted,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _money(total),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                  final list = Column(
                    children: List.generate(data.length, (i) {
                      final item = data[i];
                      final value = _num(item['total']);
                      final pct = total == 0 ? 0.0 : value / total;
                      final color = colors[i % colors.length];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .13),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _icon(_name(item)),
                                color: color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _name(item),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _money(value),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  LinearProgressIndicator(
                                    value: pct,
                                    minHeight: 7,
                                    borderRadius: BorderRadius.circular(8),
                                    backgroundColor: TerreEtOrColors.border
                                        .withValues(alpha: .55),
                                    color: color,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${(pct * 100).toStringAsFixed(1)} % du total',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: TerreEtOrColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  );
                  return c.maxWidth >= 700
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            chart,
                            const SizedBox(width: 30),
                            Expanded(child: list),
                          ],
                        )
                      : Column(
                          children: [chart, const SizedBox(height: 12), list],
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
