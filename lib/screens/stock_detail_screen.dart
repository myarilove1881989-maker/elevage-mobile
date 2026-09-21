import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/detail_widgets.dart';

class StockDetailScreen extends StatefulWidget {
  final ApiService apiService;
  final int lotId;
  const StockDetailScreen({super.key, required this.apiService, required this.lotId});
  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  Map<String, dynamic> data = {};
  bool isLoading = true;
  String? error;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final result = await widget.apiService.getStockDetail(widget.lotId);
      if (!mounted) return;
      setState(() { data = result; isLoading = false; error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e.toString(); isLoading = false; });
    }
  }
  double _number(String key) => (data[key] as num?)?.toDouble() ?? 0;
  String _value(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) return Scaffold(appBar: AppBar(title: Text(context.tr('stock'))), body: Center(child: Text(error!)));
    final initial = _number('stock_initial');
    final remaining = _number('stock_restant');
    final sold = _number('vendu');
    final lost = _number('perdu');
    final mortality = _number('mortalite');
    final theft = _number('vol');
    final donation = _number('don');
    final lossRate = initial == 0 ? 0.0 : lost / initial * 100;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('stock'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : 2;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: constraints.maxWidth < 430 ? 1.25 : 1.65,
                children: [
                  DetailMetricCard(label: 'Stock initial', value: _value(initial), caption: context.tr('units'), icon: Icons.inventory_2_outlined, color: const Color(0xFF3D7FA1)),
                  DetailMetricCard(label: 'Stock restant', value: _value(remaining), caption: context.tr('units'), icon: Icons.check_circle_outline, color: TerreEtOrColors.green),
                  DetailMetricCard(label: 'Vendu', value: _value(sold), caption: context.tr('units'), icon: Icons.shopping_cart_outlined, color: TerreEtOrColors.gold),
                  DetailMetricCard(label: 'Pertes', value: _value(lost), caption: '${lossRate.toStringAsFixed(1)} % du stock initial', icon: Icons.warning_amber_rounded, color: const Color(0xFFD85B4B)),
                ],
              ),
              const SizedBox(height: 14),
              DetailSection(
                title: 'Répartition du stock',
                subtitle: 'Situation actuelle du lot',
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 14,
                      child: initial <= 0 ? Container(color: TerreEtOrColors.border) : Row(children: [
                        if (remaining > 0) Expanded(flex: remaining.round(), child: Container(color: TerreEtOrColors.green)),
                        if (sold > 0) Expanded(flex: sold.round(), child: Container(color: TerreEtOrColors.gold)),
                        if (lost > 0) Expanded(flex: lost.round(), child: Container(color: const Color(0xFFD85B4B))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(spacing: 20, runSpacing: 12, children: [
                    _legend('Restant', remaining, TerreEtOrColors.green),
                    _legend('Vendu', sold, TerreEtOrColors.gold),
                    _legend('Mortalité', mortality, const Color(0xFFD85B4B)),
                    _legend('Vol', theft, const Color(0xFF8A5A44)),
                    _legend('Don', donation, const Color(0xFF3D7FA1)),
                  ]),
                ]),
              ),
            ],
          );
        }),
      ),
    );
  }
  Widget _legend(String label, double value, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6), Text('$label · ${_value(value)}', style: const TextStyle(color: TerreEtOrColors.muted)),
  ]);
}
