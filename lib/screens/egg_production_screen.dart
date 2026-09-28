import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';
import 'feed_distribution_screen.dart';

class EggProductionScreen extends StatefulWidget {
  final ApiService apiService;
  final int lotId;
  final String lotName;

  const EggProductionScreen({
    super.key,
    required this.apiService,
    required this.lotId,
    required this.lotName,
  });

  @override
  State<EggProductionScreen> createState() => _EggProductionScreenState();
}

class _EggProductionScreenState extends State<EggProductionScreen> {
  static const int eggsPerTray = 30;

  String trayCount(dynamic value) {
    final count = (number(value)).toInt();
    return '${count ~/ eggsPerTray} ${context.tr('egg_trays_short')} + '
        '${count % eggsPerTray} ${context.tr('egg_eggs_short')}';
  }

  Map<String, List<Map<String, dynamic>>> get collectionsByDay {
    final days = <String, List<Map<String, dynamic>>>{};
    for (final raw in collections) {
      final item = Map<String, dynamic>.from(raw as Map);
      final at = DateTime.tryParse(item['collecte_at']?.toString() ?? '')?.toLocal();
      if (at == null) continue;
      final day = MaterialLocalizations.of(context).formatMediumDate(at);
      days.putIfAbsent(day, () => []).add(item);
    }
    return days;
  }
  Map<String, dynamic>? stats;
  List<dynamic> collections = [];
  bool loading = true;
  bool saving = false;
  int periodDays = 7;
  DateTimeRange? customRange;

  DateTime get periodEnd => customRange?.end ?? DateTime.now();
  DateTime get periodStart =>
      customRange?.start ??
      DateTime.now().subtract(Duration(days: periodDays - 1));

  @override
  void initState() {
    super.initState();
    loadData();
  }

  double number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String money(dynamic value) =>
      AppSettings.instance.formatMoney(number(value), decimals: 0);

  Future<void> loadData() async {
    if (mounted) setState(() => loading = true);
    try {
      final results = await Future.wait([
        widget.apiService.getEggStatistics(
          widget.lotId,
          start: periodStart,
          end: periodEnd,
        ),
        widget.apiService.getEggCollections(
          widget.lotId,
          start: periodStart,
          end: periodEnd,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        stats = results[0] as Map<String, dynamic>;
        collections = results[1] as List<dynamic>;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> selectCustomPeriod() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: customRange,
    );
    if (range == null) return;
    setState(() => customRange = range);
    await loadData();
  }

  Future<void> showCollectionDialog() async {
    final trays = TextEditingController(text: '0');
    final remainder = TextEditingController(text: '0');
    final broken = TextEditingController(text: '0');
    final downgraded = TextEditingController(text: '0');
    final consumed = TextEditingController(text: '0');
    final note = TextEditingController();
    final now = DateTime.now();
    DateTime selectedDate = now;
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(now);
    bool submitting = false;
    final dialogRoute = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final trayNumber = int.tryParse(trays.text.trim()) ?? 0;
          final remaining = int.tryParse(remainder.text.trim()) ?? 0;
          final collected = trayNumber * eggsPerTray + remaining;
          final losses = (int.tryParse(broken.text.trim()) ?? 0) +
              (int.tryParse(downgraded.text.trim()) ?? 0) +
              (int.tryParse(consumed.text.trim()) ?? 0);
          return AlertDialog(
            title: Text(dialogContext.tr('egg_new_collection')),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton.icon(
                          key: const Key('eggCollectionDate'),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(MaterialLocalizations.of(dialogContext)
                              .formatMediumDate(selectedDate)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null && dialogContext.mounted) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                        ),
                        TextButton.icon(
                          key: const Key('eggCollectionTime'),
                          icon: const Icon(Icons.access_time),
                          label: Text(MaterialLocalizations.of(dialogContext)
                              .formatTimeOfDay(selectedTime)),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: dialogContext,
                              initialTime: selectedTime,
                            );
                            if (picked != null && dialogContext.mounted) {
                              setDialogState(() => selectedTime = picked);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(dialogContext.tr('egg_production_section')),
                    TextField(
                      key: const Key('eggFullTrays'),
                      controller: trays,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: dialogContext.tr('egg_full_trays')),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    TextField(
                      key: const Key('eggRemaining'),
                      controller: remainder,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: dialogContext.tr('egg_remaining')),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Text('${dialogContext.tr('egg_collected_total')}: $collected'),
                    const SizedBox(height: 14),
                    Text(dialogContext.tr('egg_losses_section')),
                    TextField(
                      key: const Key('eggBroken'),
                      controller: broken,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: dialogContext.tr('egg_broken')),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    TextField(
                      key: const Key('eggDowngraded'),
                      controller: downgraded,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: dialogContext.tr('egg_downgraded')),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    TextField(
                      key: const Key('eggConsumed'),
                      controller: consumed,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: dialogContext.tr('egg_consumed')),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Text('${dialogContext.tr('egg_commercializable')}: ${collected - losses}'),
                    TextField(
                      key: const Key('eggNote'),
                      controller: note,
                      decoration: InputDecoration(labelText: dialogContext.tr('egg_optional_note')),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(dialogContext, false),
                child: Text(dialogContext.tr('egg_cancel')),
              ),
              ElevatedButton(
                onPressed: submitting ? null : () async {
                  final values = [trays, remainder, broken, downgraded, consumed]
                      .map((controller) => int.tryParse(controller.text.trim())).toList();
                  if (values.any((value) => value == null || value < 0) ||
                      values[1]! >= eggsPerTray || collected == 0 || losses > collected) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(dialogContext.tr('egg_invalid_collection'))),
                    );
                    return;
                  }
                  setDialogState(() => submitting = true);
                  try {
                    await widget.apiService.createEggCollection(
                      lotId: widget.lotId,
                      collectedAt: DateTime(selectedDate.year, selectedDate.month,
                          selectedDate.day, selectedTime.hour, selectedTime.minute),
                      fullTrays: values[0]!,
                      remainingEggs: values[1]!,
                      broken: values[2]!,
                      downgraded: values[3]!,
                      consumedOrDonated: values[4]!,
                      note: note.text.trim(),
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                      setDialogState(() => submitting = false);
                    }
                  }
                },
                child: Text(dialogContext.tr('egg_save_collection')),
              ),
            ],
          );
        },
      ),
    );
    final saved = await Navigator.of(context).push(dialogRoute);
    await dialogRoute.completed;
    trays.dispose();
    remainder.dispose();
    broken.dispose();
    downgraded.dispose();
    consumed.dispose();
    note.dispose();
    if (saved == true) await loadData();
  }

  Future<void> showSaleDialog() async {
    List<dynamic> clients;
    try {
      clients = await widget.apiService.getClients();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted) return;
    int? clientId;
    String packaging = 'PLATEAU';
    final packageCount = TextEditingController();
    final packagePrice = TextEditingController();
    final cartonSize = TextEditingController(text: '360');
    final dialogRoute = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Vente d’œufs'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Client'),
                  items: clients.map<DropdownMenuItem<int>>((client) {
                    return DropdownMenuItem(
                      value: client['id'] as int,
                      child: Text(client['nom'].toString()),
                    );
                  }).toList(),
                  onChanged: (value) => clientId = value,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: packaging,
                  decoration: const InputDecoration(
                    labelText: 'Conditionnement',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'UNITE', child: Text('Unité')),
                    DropdownMenuItem(
                      value: 'DOUZAINE',
                      child: Text('Douzaine'),
                    ),
                    DropdownMenuItem(
                      value: 'PLATEAU',
                      child: Text('Plateau de 30'),
                    ),
                    DropdownMenuItem(value: 'CARTON', child: Text('Carton')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => packaging = value ?? 'PLATEAU'),
                ),
                _numberField(packageCount, 'Nombre de conditionnements'),
                if (packaging == 'CARTON')
                  _numberField(cartonSize, 'Œufs par carton'),
                TextField(
                  controller: packagePrice,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Prix par conditionnement (${AppSettings.instance.currency.symbol})',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (clientId == null || saving) return;
                saving = true;
                try {
                  await widget.apiService.createEggSale(
                    lotId: widget.lotId,
                    clientId: clientId!,
                    packaging: packaging,
                    packageCount: int.parse(packageCount.text),
                    packagePrice: double.parse(
                      packagePrice.text.replaceAll(',', '.'),
                    ),
                    eggsPerPackage: packaging == 'CARTON'
                        ? int.parse(cartonSize.text)
                        : null,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                } finally {
                  saving = false;
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    final saved = await Navigator.of(context).push(dialogRoute);
    await dialogRoute.completed;
    packageCount.dispose();
    packagePrice.dispose();
    cartonSize.dispose();
    if (saved == true) await loadData();
  }

  Future<void> showFeedDialog() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeedDistributionScreen(
          apiService: widget.apiService,
          lotId: widget.lotId,
          lotName: widget.lotName,
        ),
      ),
    );
    if (mounted) await loadData();
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: terreEtOrTheme(context),
      child: Scaffold(
        appBar: AppBar(title: Text('Ponte · ${widget.lotName}')),
        body: RefreshIndicator(
          onRefresh: loadData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              TerreEtOrHeader(
                icon: Icons.egg_outlined,
                title: 'Production d’œufs',
                subtitle: 'Collectes, stock, ventes et alimentation',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('7 jours'),
                    selected: customRange == null && periodDays == 7,
                    onSelected: (_) {
                      setState(() {
                        periodDays = 7;
                        customRange = null;
                      });
                      loadData();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('30 jours'),
                    selected: customRange == null && periodDays == 30,
                    onSelected: (_) {
                      setState(() {
                        periodDays = 30;
                        customRange = null;
                      });
                      loadData();
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: selectCustomPeriod,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      customRange == null ? 'Période' : 'Personnalisée',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (stats != null) ...[
                GridView.count(
                  crossAxisCount:
                      MediaQuery.sizeOf(context).width >= 850 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                  children: [
                    _metric(
                      'Poules vivantes',
                      stats!['nombre_poules_vivantes'],
                      Icons.pets,
                    ),
                    _metric(
                      'Œufs produits',
                      stats!['oeufs_collectes'],
                      Icons.egg_outlined,
                    ),
                    _metric(
                      'Taux de ponte',
                      '${number(stats!['taux_ponte']).toStringAsFixed(1)} %',
                      Icons.percent,
                    ),
                    _metric(
                      'Stock d’œufs',
                      stats!['stock_oeufs'],
                      Icons.inventory_2_outlined,
                    ),
                    _metric(
                      context.tr('egg_tray_equivalent'),
                      trayCount(stats!['stock_oeufs']),
                      Icons.grid_view,
                    ),
                    _metric(
                      'Œufs vendus',
                      stats!['oeufs_vendus'],
                      Icons.shopping_cart_outlined,
                    ),
                    _metric(
                      'CA œufs',
                      money(stats!['chiffre_affaires_oeufs']),
                      Icons.payments_outlined,
                    ),
                    _metric(
                      'Marge œufs',
                      money(stats!['marge_oeufs']),
                      Icons.trending_up,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TerreEtOrPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Qualité et alimentation',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Commercialisables : ${stats!['oeufs_commercialisables']}',
                      ),
                      Text(
                        'Cassés : ${stats!['oeufs_casses']} · Déclassés : ${stats!['oeufs_declasses']}',
                      ),
                      Text(
                        'Aliment : ${number(stats!['consommation_aliment_kg']).toStringAsFixed(2)} kg',
                      ),
                      Text('Coût par œuf : ${money(stats!['cout_par_oeuf'])}'),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  final columns = constraints.maxWidth >= 760
                      ? 3
                      : constraints.maxWidth >= 500
                          ? 2
                          : 1;
                  final buttonWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      SizedBox(
                        width: buttonWidth,
                        child: ElevatedButton.icon(
                          onPressed: showCollectionDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Nouvelle collecte'),
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: ElevatedButton.icon(
                          onPressed: showSaleDialog,
                          icon: const Icon(Icons.shopping_cart_checkout),
                          label: const Text('Vendre des œufs'),
                        ),
                      ),
                      SizedBox(
                        width: buttonWidth,
                        child: ElevatedButton.icon(
                          onPressed: showFeedDialog,
                          icon: const Icon(Icons.grass_outlined),
                          label: const Text('Alimentation'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              Text(
                'Historique des collectes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (!loading && collections.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Aucune collecte sur cette période.'),
                  ),
                ),
              ...collectionsByDay.entries.expand((day) => [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                      child: Text(day.key,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    ...day.value.map((item) {
                      final at = DateTime.parse(item['collecte_at'].toString()).toLocal();
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: TerreEtOrColors.paleGold,
                            child: Icon(Icons.egg_outlined, color: TerreEtOrColors.gold),
                          ),
                          title: Text(trayCount(item['nombre_collecte'])),
                          subtitle: Text(
                            '${context.tr('egg_collected_total')}: ${item['nombre_collecte']} · '
                            '${context.tr('egg_commercializable')}: ${item['nombre_commercialisable']}\n'
                            '${context.tr('egg_broken')}: ${item['nombre_casses']} · '
                            '${context.tr('egg_downgraded')}: ${item['nombre_declasses']} · '
                            '${context.tr('egg_consumed')}: ${item['nombre_consommes_donnes']}',
                          ),
                          trailing: Text(MaterialLocalizations.of(context)
                              .formatTimeOfDay(TimeOfDay.fromDateTime(at))),
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      child: Text(
                        '${context.tr('egg_daily_total')}: '
                        '${day.value.fold<int>(0, (sum, item) => sum + number(item['nombre_collecte']).toInt())} · '
                        '${context.tr('egg_commercializable')}: '
                        '${day.value.fold<int>(0, (sum, item) => sum + number(item['nombre_commercialisable']).toInt())}',
                      ),
                    ),
                  ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, dynamic value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: TerreEtOrColors.gold),
            const SizedBox(height: 7),
            Text(
              value?.toString() ?? '0',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: TerreEtOrColors.ink,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: TerreEtOrColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
