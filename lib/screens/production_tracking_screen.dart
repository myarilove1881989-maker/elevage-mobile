import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/terre_et_or_theme.dart';
import 'egg_production_screen.dart';

class ProductionTrackingScreen extends StatefulWidget {
  final ApiService apiService;

  const ProductionTrackingScreen({super.key, required this.apiService});

  @override
  State<ProductionTrackingScreen> createState() =>
      _ProductionTrackingScreenState();
}

class _ProductionTrackingScreenState extends State<ProductionTrackingScreen> {
  List<dynamic> species = [];
  List<dynamic> lots = [];
  int? selectedSpeciesId;
  int? selectedLotId;
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait([
        widget.apiService.getEspeces(),
        widget.apiService.getLots(),
      ]);
      if (!mounted) return;
      setState(() {
        species = results[0];
        lots = results[1];
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorMessage = context.tr('production_tracking_load_error');
        loading = false;
      });
    }
  }

  List<dynamic> get filteredLots {
    if (selectedSpeciesId == null) return [];
    return lots
        .where((lot) => _asInt(lot['espece']) == selectedSpeciesId)
        .toList();
  }

  Map<String, dynamic>? get selectedLot {
    if (selectedLotId == null) return null;
    for (final lot in lots) {
      if (_asInt(lot['id']) == selectedLotId) {
        return Map<String, dynamic>.from(lot as Map);
      }
    }
    return null;
  }

  String _productionTypeLabel(BuildContext context, String type) {
    switch (type) {
      case 'OEUFS':
        return context.tr('production_type_eggs');
      case 'REPRODUCTION':
        return context.tr('production_type_reproduction');
      case 'AUTRE':
        return context.tr('production_type_other');
      case 'CHAIR':
      default:
        return context.tr('production_type_meat');
    }
  }

  Widget _statusCard({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return TerreEtOrPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: TerreEtOrColors.gold, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: TerreEtOrColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: TerreEtOrColors.muted)),
          if (action != null) ...[
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: action),
          ],
        ],
      ),
    );
  }

  Widget _productionContent(Map<String, dynamic> lot) {
    final type = lot['type_production']?.toString() ?? 'CHAIR';
    switch (type) {
      case 'OEUFS':
        return _statusCard(
          icon: Icons.egg_outlined,
          title: context.tr('laying_tracking'),
          message: context.tr('laying_tracking_available'),
          action: ElevatedButton.icon(
            key: const Key('openEggTrackingButton'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EggProductionScreen(
                    apiService: widget.apiService,
                    lotId: _asInt(lot['id'])!,
                    lotName: lot['nom']?.toString() ?? context.tr('batch'),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.egg_outlined),
            label: Text(context.tr('open_laying_tracking')),
          ),
        );
      case 'REPRODUCTION':
        return _statusCard(
          icon: Icons.autorenew,
          title: context.tr('reproduction_tracking'),
          message: context.tr('reproduction_tracking_future'),
        );
      case 'AUTRE':
        return _statusCard(
          icon: Icons.info_outline,
          title: context.tr('production_tracking'),
          message: context.tr('no_specialized_tracking'),
        );
      case 'CHAIR':
      default:
        return _statusCard(
          icon: Icons.show_chart,
          title: context.tr('growth_tracking'),
          message: context.tr('growth_tracking_future'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLot = selectedLot;
    return Theme(
      data: terreEtOrTheme(context),
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('production_tracking'))),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadOptions,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    TerreEtOrHeader(
                      icon: Icons.monitor_heart_outlined,
                      title: context.tr('production_tracking'),
                      subtitle: context.tr('production_tracking_subtitle'),
                    ),
                    if (errorMessage != null)
                      _statusCard(
                        icon: Icons.error_outline,
                        title: context.tr('error'),
                        message: errorMessage!,
                      )
                    else ...[
                      DropdownButtonFormField<int>(
                        key: const Key('productionSpeciesDropdown'),
                        initialValue: selectedSpeciesId,
                        decoration: InputDecoration(
                          labelText: context.tr('species'),
                          prefixIcon: const Icon(Icons.pets_outlined),
                        ),
                        items: species
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: _asInt(item['id']),
                                child: Text(item['nom']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedSpeciesId = value;
                            selectedLotId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        key: const Key('productionLotDropdown'),
                        initialValue: selectedLotId,
                        decoration: InputDecoration(
                          labelText: context.tr('batch'),
                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                        ),
                        items: filteredLots
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: _asInt(item['id']),
                                child: Text(item['nom']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: selectedSpeciesId == null ||
                                filteredLots.isEmpty
                            ? null
                            : (value) => setState(() => selectedLotId = value),
                      ),
                      if (selectedSpeciesId != null && filteredLots.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            context.tr('no_batch_for_species'),
                            style: const TextStyle(
                              color: TerreEtOrColors.muted,
                            ),
                          ),
                        ),
                      if (currentLot != null) ...[
                        const SizedBox(height: 14),
                        InputDecorator(
                          decoration: InputDecoration(
                            labelText: context.tr('production_type'),
                            prefixIcon: const Icon(Icons.category_outlined),
                          ),
                          child: Text(
                            _productionTypeLabel(
                              context,
                              currentLot['type_production']?.toString() ??
                                  'CHAIR',
                            ),
                            key: const Key('productionTypeValue'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _productionContent(currentLot),
                      ],
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
