import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/terre_et_or_theme.dart';

double? _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

String _kg(dynamic value) {
  final number = _number(value);
  if (number == null) return '—';
  return '${number.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')} kg';
}

String _dateTime(dynamic value) {
  final parsed = DateTime.tryParse('$value')?.toLocal();
  if (parsed == null) return '$value';
  final day = parsed.day.toString().padLeft(2, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '$day/$month/${parsed.year} • $hour:$minute';
}

class GrowthTrackingScreen extends StatefulWidget {
  final ApiService apiService;
  final int lotId;
  final String lotName;

  const GrowthTrackingScreen({
    super.key,
    required this.apiService,
    required this.lotId,
    required this.lotName,
  });

  @override
  State<GrowthTrackingScreen> createState() => _GrowthTrackingScreenState();
}

class _GrowthTrackingScreenState extends State<GrowthTrackingScreen> {
  final _countController = TextEditingController();
  final _weightController = TextEditingController();
  final _noteController = TextEditingController();
  Map<String, dynamic> tracking = {};
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _countController.dispose();
    _weightController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final result = await widget.apiService.getProductionWeights(widget.lotId);
      if (!mounted) return;
      setState(() {
        tracking = result;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = context.tr('growth_load_error');
        loading = false;
      });
    }
  }

  Future<void> _addWeighing() async {
    final countController = _countController..clear();
    final weightController = _weightController..clear();
    final noteController = _noteController..clear();
    final formKey = GlobalKey<FormState>();
    DateTime weighedAt = DateTime.now();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('add_weighing')),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: context.tr('animals_weighed'),
                      prefixIcon: const Icon(Icons.groups_outlined),
                    ),
                    validator: (value) {
                      final count = int.tryParse(value ?? '');
                      if (count == null || count <= 0) {
                        return context.tr('growth_invalid_count');
                      }
                      final current = (tracking['effectif_actuel'] as num?)?.toInt() ?? 0;
                      if (count > current) {
                        return context.tr('growth_sample_too_large');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: weightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: context.tr('sample_total_weight'),
                      suffixText: 'kg',
                      prefixIcon: const Icon(Icons.monitor_weight_outlined),
                    ),
                    validator: (value) {
                      final weight = double.tryParse(
                        (value ?? '').replaceAll(',', '.'),
                      );
                      return weight == null || weight <= 0
                          ? context.tr('growth_invalid_weight')
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: weighedAt,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(weighedAt),
                        );
                        if (time == null) return;
                        setDialogState(() {
                          weighedAt = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_dateTime(weighedAt.toIso8601String())),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: context.tr('growth_note_optional'),
                      prefixIcon: const Icon(Icons.notes_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: Text(context.tr('save')),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() => saving = true);
      try {
        await widget.apiService.createProductionWeight(
          lotId: widget.lotId,
          weighedAt: weighedAt,
          animalsWeighed: int.parse(countController.text),
          sampleWeightKg: double.parse(weightController.text.replaceAll(',', '.')),
          note: noteController.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('growth_saved'))),
        );
        await _load();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('growth_save_error'))),
        );
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  Widget _metric(String title, String value, IconData icon) => Expanded(
        child: TerreEtOrPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: TerreEtOrColors.gold),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(color: TerreEtOrColors.muted)),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: TerreEtOrColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final measurements = List<dynamic>.from(tracking['pesees'] ?? const [])
        .reversed
        .toList();
    final average = tracking['dernier_poids_moyen_kg'];
    final biomass = tracking['biomasse_estimee_kg'];
    final gmq = tracking['gmq_g_par_jour'];
    final count = tracking['effectif_actuel']?.toString() ?? '0';

    return Theme(
      data: terreEtOrTheme(context),
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('growth_tracking'))),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    TerreEtOrHeader(
                      icon: Icons.show_chart,
                      title: widget.lotName,
                      subtitle: context.tr('growth_tracking'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      TerreEtOrPanel(child: Text(error!)),
                    ] else ...[
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final metrics = [
                            _metric(context.tr('current_count'), '$count ${context.tr('units')}', Icons.groups_outlined),
                            _metric(context.tr('last_average_weight'), _kg(average), Icons.monitor_weight_outlined),
                            _metric(context.tr('estimated_biomass'), _kg(biomass), Icons.scale_outlined),
                            _metric(
                              context.tr('daily_gain'),
                              gmq == null
                                  ? '—'
                                  : '${_number(gmq)!.toStringAsFixed(1)} ${context.tr('gain_unit')}',
                              Icons.trending_up,
                            ),
                          ];
                          if (constraints.maxWidth < 700) {
                            return Column(
                              children: [
                                for (var index = 0; index < metrics.length; index += 2)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        metrics[index],
                                        const SizedBox(width: 10),
                                        metrics[index + 1],
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var index = 0; index < metrics.length; index++) ...[
                                if (index > 0) const SizedBox(width: 10),
                                metrics[index],
                              ],
                            ],
                          );
                        },
                      ),
                      if (gmq == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            context.tr('gmq_after_second_weighing'),
                            style: const TextStyle(color: TerreEtOrColors.muted),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: saving ? null : _addWeighing,
                          icon: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add),
                          label: Text(context.tr('add_weighing')),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.tr('weighing_history'),
                        style: const TextStyle(
                          color: TerreEtOrColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (measurements.isEmpty)
                        TerreEtOrPanel(child: Text(context.tr('growth_empty')))
                      else
                        for (final item in measurements)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TerreEtOrPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _dateTime(item['pesee_at']),
                                    style: const TextStyle(
                                      color: TerreEtOrColors.ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text('${item['nombre_animaux_peses']} ${context.tr('animals_weighed').toLowerCase()}'),
                                  Text('${context.tr('sample_total_weight')}: ${_kg(item['poids_total_kg'])}'),
                                  Text('${context.tr('average_weight')}: ${_kg(item['poids_moyen_kg'])}'),
                                  if (item['gmq_g_par_jour'] != null)
                                    Text('${context.tr('daily_gain')}: ${_number(item['gmq_g_par_jour'])!.toStringAsFixed(1)} ${context.tr('gain_unit')}'),
                                  if ((item['note'] ?? '').toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(item['note'].toString()),
                                    ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
