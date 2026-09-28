import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';

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
    final total = TextEditingController();
    final broken = TextEditingController(text: '0');
    final downgraded = TextEditingController(text: '0');
    final consumed = TextEditingController(text: '0');
    final note = TextEditingController();
    final dialogRoute = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle collecte'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numberField(total, 'Œufs collectés'),
              _numberField(broken, 'Œufs cassés'),
              _numberField(downgraded, 'Sales ou déclassés'),
              _numberField(consumed, 'Consommés ou donnés'),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note facultative',
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
              if (saving) return;
              saving = true;
              try {
                await widget.apiService.createEggCollection(
                  lotId: widget.lotId,
                  collectedAt: DateTime.now(),
                  total: int.parse(total.text),
                  broken: int.tryParse(broken.text) ?? 0,
                  downgraded: int.tryParse(downgraded.text) ?? 0,
                  consumedOrDonated: int.tryParse(consumed.text) ?? 0,
                  note: note.text.trim(),
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
    );
    final saved = await Navigator.of(context).push(dialogRoute);
    await dialogRoute.completed;
    total.dispose();
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
    List<dynamic> expenses;
    try {
      final lot = await widget.apiService.getLotDetail(widget.lotId);
      expenses = (lot['depenses'] as List<dynamic>?) ?? [];
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted) return;
    int? expenseId;
    final quantity = TextEditingController();
    final price = TextEditingController();
    final note = TextEditingController();
    final dialogRoute = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Alimentation du jour'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Dépense déjà enregistrée (facultatif)',
                ),
                items: [
                  const DropdownMenuItem(
                    value: 0,
                    child: Text('Aucune : coût estimé'),
                  ),
                  ...expenses.map(
                    (expense) => DropdownMenuItem<int>(
                      value: expense['id'] as int,
                      child: Text(
                        '#${expense['id']} · ${money(expense['montant'])}',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => expenseId = value == 0 ? null : value,
              ),
              const Text(
                'Liez la dépense existante pour éviter de compter deux fois le même coût. Le prix/kg est ignoré si une dépense est liée.',
              ),
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantité consommée (kg)',
                ),
              ),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      'Prix par kg facultatif (${AppSettings.instance.currency.symbol})',
                ),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note facultative',
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
              if (saving) return;
              saving = true;
              try {
                await widget.apiService.createFeedConsumption(
                  expenseId: expenseId,
                  lotId: widget.lotId,
                  quantityKg: double.parse(quantity.text.replaceAll(',', '.')),
                  pricePerKg: price.text.trim().isEmpty
                      ? null
                      : double.parse(price.text.replaceAll(',', '.')),
                  note: note.text.trim(),
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
    );
    final saved = await Navigator.of(context).push(dialogRoute);
    await dialogRoute.completed;
    quantity.dispose();
    price.dispose();
    note.dispose();
    if (saved == true) await loadData();
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
                      'Plateaux',
                      number(stats!['equivalent_plateaux']).toStringAsFixed(2),
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
              ...collections.map(
                (item) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: TerreEtOrColors.paleGold,
                      child: Icon(
                        Icons.egg_outlined,
                        color: TerreEtOrColors.gold,
                      ),
                    ),
                    title: Text('${item['nombre_collecte']} œufs collectés'),
                    subtitle: Text(
                      '${item['nombre_commercialisable']} commercialisables · '
                      '${item['nombre_casses']} cassés · ${item['nombre_declasses']} déclassés',
                    ),
                    trailing: Text(
                      item['collecte_at']
                              ?.toString()
                              .replaceFirst('T', ' ')
                              .substring(0, 16) ??
                          '',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
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
