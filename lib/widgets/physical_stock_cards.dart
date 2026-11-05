import '../widgets/v2_components.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/permission_contract.dart';
import '../services/physical_stock_summary.dart';
import '../offline/health_task_state.dart';
import '../screens/health_agenda_screen.dart';
import '../screens/add_depense_screen.dart';
import '../screens/feed_distribution_screen.dart';
import '../screens/vaccination_screen.dart';
import 'dashboard_kpi_card.dart';

class PhysicalStockCards extends StatefulWidget {
  const PhysicalStockCards({
    super.key,
    required this.api,
    this.species,
    this.lot,
    this.revision = 0,
    this.compact = false,
    this.trackingKind,
  });
  final ApiService api;
  final int? species, lot;
  final int revision;
  final bool compact;
  final bool? trackingKind;
  @override
  State<PhysicalStockCards> createState() => _PhysicalStockCardsState();
}

class _PhysicalStockCardsState extends State<PhysicalStockCards> {
  Map<String, dynamic>? feed, vaccine;
  List tasks = [];
  List recentVaccinations = [];
  bool recentUnavailable = false;
  bool cachedStock = false;
  PermissionContract? rights;
  String? error, identity;
  int? expiryDays, upcomingDays;
  bool agendaUnavailable = false;
  bool loading = true;
  int generation = 0;
  Timer? clock;
  String? observedIdentity;
  int? selectedSpecies, selectedLot;
  String get scope => 'stock-alerts:${rights!.farmId}:${rights!.userId}';
  @override
  void initState() {
    super.initState();
    selectedSpecies = widget.species;
    selectedLot = widget.lot;
    ApiService.businessChanges.addListener(changed);
    widget.api.sessionChanges?.addListener(sessionChanged);
    load();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void changed() {
    load();
  }

  void sessionChanged() {
    if (observedIdentity != ApiService.sessionIdentity) load();
  }

  @override
  void didUpdateWidget(covariant PhysicalStockCards old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api) {
      old.api.sessionChanges?.removeListener(sessionChanged);
      widget.api.sessionChanges?.addListener(sessionChanged);
    }
    if (old.species != widget.species || old.lot != widget.lot) {
      selectedSpecies = widget.species;
      selectedLot = widget.lot;
    }
    if (old.api != widget.api || old.revision != widget.revision) load();
  }

  @override
  void dispose() {
    clock?.cancel();
    ApiService.businessChanges.removeListener(changed);
    widget.api.sessionChanges?.removeListener(sessionChanged);
    super.dispose();
  }

  Future<void> load() async {
    final ticket = ++generation, captured = ApiService.sessionIdentity;
    observedIdentity = captured;
    if (mounted)
      setState(() {
        loading = true;
        error = null;
        feed = null;
        vaccine = null;
        tasks = [];
        rights = null;
      });
    try {
      final caps = await widget.api.get('/me/capabilities/');
      final policy = PermissionContract.decode(
        Map<String, dynamic>.from(caps['permission_contract'] as Map),
        userId: caps['user'] as int,
        farmId: caps['exploitation'] as int,
        role: caps['role'] as String,
        rightsVersion: caps['membership']['version'] as int,
        allowHttpV2: true,
      );
      if (!policy.allows('stocks.read'))
        throw StateError('Consultation des stocks non autorisée.');
      // The cache marker belongs to the last API read: capture each snapshot
      // before another response can replace that marker.
      final feedData = await widget.api.get('/feed-supplies/?presentation=1');
      final feedCached = widget.api.lastReadWasCached;
      final vaccineData = await widget.api.get('/vaccine-supplies/');
      final cached = feedCached || widget.api.lastReadWasCached;
      final data = [feedData, vaccineData];
      List recent = [];
      var failedRecent = false;
      if (widget.trackingKind == false && policy.allows('vaccinations.read')) {
        try {
          recent = await widget.api.get('/vaccinations/') as List;
        } catch (_) {
          failedRecent = true;
        }
      }
      List agenda = [];
      var failedAgenda = false;
      if (policy.allows('agenda.read')) {
        try {
          agenda = await widget.api.get('/tasks/') as List;
        } catch (_) {
          failedAgenda = true;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      if (!mounted ||
          ticket != generation ||
          captured != ApiService.sessionIdentity)
        return;
      for (final snapshot in data) {
        if (snapshot['exploitation'] != null &&
            snapshot['exploitation'] != policy.farmId)
          throw StateError('Stock hors exploitation.');
      }
      setState(() {
        identity = captured;
        rights = policy;
        feed = Map<String, dynamic>.from(data[0] as Map);
        vaccine = Map<String, dynamic>.from(data[1] as Map);
        tasks = agenda;
        agendaUnavailable = failedAgenda;
        recentVaccinations = recent;
        recentUnavailable = failedRecent;
        cachedStock = cached;
        expiryDays = prefs.getInt(
          'stock-alerts:${policy.farmId}:${policy.userId}:expiry',
        );
        upcomingDays = prefs.getInt(
          'stock-alerts:${policy.farmId}:${policy.userId}:upcoming',
        );
        loading = false;
      });
    } catch (_) {
      if (mounted && ticket == generation)
        setState(() {
          loading = false;
          error =
              'Stocks indisponibles ou accès non autorisé. Actualisez votre connexion.';
        });
    }
  }

  bool get current => identity == ApiService.sessionIdentity && rights != null;
  int? get species {
    if (selectedSpecies != null) return selectedSpecies;
    for (final lot in feed?['lots'] as List? ?? const []) {
      if (lot['id'] == selectedLot) return lot['espece_id'] as int?;
    }
    return null;
  }

  Map<String, dynamic> get fs =>
      feedSummary(feed!, species: species, lot: selectedLot);
  Map<String, dynamic> get vs => vaccineSummary(
    vaccine!,
    DateTime.now().toUtc(),
    species: species,
    lot: selectedLot,
    warningDays: expiryDays,
  );
  String state(Map data) {
    final pending = (data['pending_operations'] as List? ?? const []).length,
        review = (data['review_operations'] as List? ?? const []).length;
    if (review > 0) return 'Une opération nécessite votre attention.';
    if (pending > 0) return 'Synchronisation en attente';
    if (cachedStock || data['local_estimate'] == true || data['as_of'] == null)
      return 'Stock à actualiser';
    return 'Stock actualisé';
  }

  Widget card(bool isFeed) {
    final sum = isFeed ? fs : vs, data = isFeed ? feed! : vaccine!;
    final alerts = <String>[];
    if (isFeed) {
      for (final p in sum['details']) {
        if (p['archived'] == true) continue;
        if (p['empty'] == true) {
          alerts.add('Rupture : ${p['name']}');
        } else if (p['low'] == true) {
          alerts.add('Stock faible : ${p['name']}');
        }
      }
    } else {
      if (sum['expired'] > 0) alerts.add('${sum['expired']} doses périmées');
      if (sum['soon'] > 0)
        alerts.add('${sum['soon']} flacons proches de péremption');
      for (final p in sum['details']) {
        if (p['low'] == true && p['archived'] != true)
          alerts.add('Stock faible : ${p['name']}');
      }
    }
    return Card(
      child: InkWell(
        onTap: () => details(isFeed),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isFeed ? Icons.grass : Icons.vaccines,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isFeed ? "Stock d’aliments" : "Stock de vaccins",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isFeed
                    ? '${sum['confirmed']} kg confirmés'
                    : '${sum['usable']} doses utilisables · ${sum['vials']} flacons disponibles',
                style: const TextStyle(fontSize: 18),
              ),
              Text(
                isFeed
                    ? 'Estimé : ${sum['estimated']} kg'
                    : 'Estimé : ${sum['estimated']} doses utilisables',
              ),
              if (!isFeed && data['local_estimate'] == true)
                const Text(
                  'Estimation sur flacons confirmés ; réceptions en attente non incluses.',
                  style: TextStyle(fontSize: 12),
                ),
              if (!isFeed)
                Text(
                  '${sum['expired']} périmées · ${sum['unusable']} inutilisables · ${sum['physical']} physiquement présentes',
                ),
              Text(state(data), style: Theme.of(context).textTheme.bodySmall),
              if ((isFeed
                  ? num.parse('${sum['estimated']}') < 0
                  : (sum['estimated'] as int) < 0))
                const Text(
                  'Estimation négative : stock à réconcilier avant utilisation.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              if (alerts.isNotEmpty)
                Text(
                  '${alerts.take(2).join(' · ')}${alerts.length > 2 ? ' · +${alerts.length - 2} alertes' : ''}',
                  style: const TextStyle(color: Colors.deepOrange),
                ),
              const Text(
                'Détails, seuils et historique',
                style: TextStyle(color: Colors.green),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> details(bool isFeed) async {
    final captured = identity,
        data = isFeed ? feed! : vaccine!,
        sum = isFeed ? fs : vs;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _StockScope(
        allowed: () => current,
        changes: widget.api.sessionChanges,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .8,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  isFeed ? "Stock d’aliments" : "Stock de vaccins",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(state(data)),
                if (selectedLot != null)
                  const Text(
                    'Inclut le stock partagé de cette espèce et le stock réservé au lot. Ne pas additionner les vues de lots.',
                  ),
                if (selectedSpecies != null || selectedLot != null)
                  const Text(
                    'Seuils comparés au total du produit, sans filtre.',
                  ),
                for (final p in sum['details'])
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p['name']}${p['archived'] == true ? ' (archivé)' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            isFeed
                                ? 'Confirmé : ${consumableQuantity(p['confirmed'])} kg · estimé : ${consumableQuantity(p['estimated'])} kg\nPartagé : ${consumableQuantity(p['shared'])} kg · réservé : ${consumableQuantity(p['reserved'])} kg'
                                : '${p['usable']} doses utilisables · estimé : ${p['estimated']}\n${p['vials']} flacons disponibles · ${p['expired']} doses périmées · ${p['unusable']} inutilisables',
                          ),
                          Text(
                            'Seuil : ${p['alert_threshold'] ?? 'non renseigné'} ${isFeed ? 'kg' : 'doses'}',
                          ),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => history(p),
                                child: const Text('Historique'),
                              ),
                              if (rights?.role == 'OWNER')
                                TextButton(
                                  onPressed: () async {
                                    if (captured != ApiService.sessionIdentity)
                                      return;
                                    await threshold(
                                      p,
                                      isFeed,
                                      fromDetails: true,
                                    );
                                  },
                                  child: const Text('Configurer le seuil'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((data['review_operations'] as List? ?? []).isNotEmpty)
                  const Text(
                    'Des opérations nécessitent une réconciliation. Consultez l’historique des opérations ; elles restent conservées.',
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> threshold(
    Map product,
    bool isFeed, {
    bool fromDetails = false,
  }) async {
    final captured = identity,
        controller = TextEditingController(
          text: '${product['alert_threshold'] ?? '0'}',
        );
    String? failure;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => _StockScope(
        allowed: () => current,
        changes: widget.api.sessionChanges,
        child: StatefulBuilder(
          builder: (context, setDialog) => V2AlertDialog(
            title: const Text('Seuil de stock faible'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isFeed
                      ? 'Seuil en kilogrammes, au niveau de l’exploitation.'
                      : 'Seuil en doses entières, au niveau de l’exploitation.',
                ),
                V2Field(child:TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const V2InputDecoration(
                    labelText: 'Seuil (0 désactive le stock faible)',),
                )),
                if (failure != null) Text(failure!),
                const Text('Configuration avec connexion requise.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () async {
                  if (captured != ApiService.sessionIdentity) return;
                  final value = controller.text.trim();
                  if (!RegExp(
                    isFeed ? r'^\d{1,11}(?:\.\d{1,3})?$' : r'^\d{1,11}$',
                  ).hasMatch(value)) {
                    setDialog(() => failure = 'Quantité invalide.');
                    return;
                  }
                  try {
                    await widget.api
                        .patch('/supply-products/${product['id']}/threshold/', {
                          'alert_threshold': value,
                          'expected_threshold':
                              '${product['alert_threshold'] ?? '0'}',
                        });
                    if (context.mounted &&
                        captured == ApiService.sessionIdentity)
                      Navigator.pop(context, true);
                  } catch (_) {
                    if (context.mounted)
                      setDialog(
                        () => failure =
                            'Modification non confirmée. Actualisez avant de réessayer.',
                      );
                  }
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
    final saved = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (saved == true && mounted && captured == ApiService.sessionIdentity) {
      if (fromDetails) Navigator.pop(context);
      await load();
    }
  }

  Future<void> history(Map product) async {
    final captured = identity;
    final rows = <dynamic>[];
    int? before;
    bool loading = true;
    String? failure;
    Future<void> page(StateSetter update) async {
      try {
        final result = await widget.api.get(
          '/supply-products/${product['id']}/history/${before == null ? '' : '?before=$before'}',
        );
        if (!mounted || captured != ApiService.sessionIdentity) return;
        update(() {
          rows.addAll(result['results'] as List);
          before = result['next_before'] as int?;
          loading = false;
        });
      } catch (_) {
        if (mounted && captured == ApiService.sessionIdentity)
          update(() {
            failure =
                'Historique indisponible. Une connexion est requise pour les pages non mises en cache.';
            loading = false;
          });
      }
    }

    var started = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          if (!started) {
            started = true;
            scheduleMicrotask(
              () => page((fn) {
                if (context.mounted) update(fn);
              }),
            );
          }
          return _StockScope(
            allowed: () => current,
            changes: widget.api.sessionChanges,
            child: SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .75,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Historique · ${product['name']}'),
                    const Text(
                      'Achats, distributions, vaccinations et corrections. Les opérations en attente restent visibles dans l’historique des opérations.',
                    ),
                    for (final row in rows)
                      ListTile(
                        title: Text(
                          '${movementLabel(row['kind'])} — ${product['name']} — ${row['kind']=='DISTRIBUTION'?consumableQuantity(row['quantity']).replaceFirst(RegExp(r"^-"),""):consumableQuantity(row['quantity'])} ${(feed?['products'] as List? ?? const []).any((p)=>p['id']==product['id'])?'kg':(vaccine?['products'] as List? ?? const []).any((p)=>p['id']==product['id'])?'doses':''}',
                        ),
                        subtitle: Text(
                          '${speciesName(row['species'])} · ${row['kind']=='DISTRIBUTION'?(row['destination_lot']==null?'Destinataire non renseigné':lotName(row['destination_lot'])):(row['lot']==null?'Stock partagé':lotName(row['lot']))} · ${day(row['at'])}\n${row['reason'] ?? ''}',
                        ),
                      ),
                    if (loading)
                      const Center(child: CircularProgressIndicator()),
                    if (failure != null) Text(failure!),
                    if (!loading && before != null)
                      TextButton(
                        onPressed: () {
                          update(() => loading = true);
                          page((fn) {
                            if (context.mounted) update(fn);
                          });
                        },
                        child: const Text('Voir plus'),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> settings() async {
    final captured = identity;
    final expiry = TextEditingController(text: expiryDays?.toString() ?? ''),
        upcoming = TextEditingController(text: upcomingDays?.toString() ?? '');
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => _StockScope(
        allowed: () => current,
        changes: widget.api.sessionChanges,
        child: V2AlertDialog(
          title: const Text('Alertes visuelles'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choisissez vos horizons en jours. Vide : alerte anticipée désactivée. Aucun protocole vaccinal n’est proposé.',
              ),
              V2Field(child:TextField(
                controller: expiry,
                decoration: const V2InputDecoration(
                  labelText: 'Péremption dans … jours',),
              )),
              V2Field(child:TextField(
                controller: upcoming,
                decoration: const V2InputDecoration(
                  labelText: 'Vaccination dans … jours',),
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () async {
                int? parse(String s) =>
                    s.trim().isEmpty ? null : int.tryParse(s.trim());
                final e = parse(expiry.text), u = parse(upcoming.text);
                if ((expiry.text.trim().isNotEmpty &&
                        (e == null || e < 0 || e > 365)) ||
                    (upcoming.text.trim().isNotEmpty &&
                        (u == null || u < 0 || u > 365)))
                  return;
                if (captured != ApiService.sessionIdentity) return;
                final key = scope;
                final prefs = await SharedPreferences.getInstance();
                if (captured != ApiService.sessionIdentity) return;
                for (final pair in {'expiry': e, 'upcoming': u}.entries) {
                  if (pair.value == null) {
                    await prefs.remove('$key:${pair.key}');
                  } else {
                    await prefs.setInt('$key:${pair.key}', pair.value!);
                  }
                }
                if (context.mounted && captured == ApiService.sessionIdentity)
                  Navigator.pop(context, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    final saved = await Navigator.of(context).push(route);
    await route.completed;
    expiry.dispose();
    upcoming.dispose();
    if (saved == true && mounted) await load();
  }

  bool get uncertain =>
      cachedStock ||
      !current ||
      feed == null ||
      vaccine == null ||
      [feed, vaccine].any(
        (d) =>
            d?['local_estimate'] == true ||
            (d?['pending_operations'] as List? ?? []).isNotEmpty ||
            (d?['review_operations'] as List? ?? []).isNotEmpty,
      );

  Widget compactCard() {
    Widget level(bool isFeed) {
      final ready =
          !loading &&
          error == null &&
          current &&
          feed != null &&
          vaccine != null;
      final value = ready
          ? consumableLevel(
              (isFeed ? fs : vs)['details'] as List,
              feed: isFeed,
              filtered: species != null || selectedLot != null,
              uncertain: uncertain,
            )
          : ConsumableLevel.neutral;
      final attention = [
        feed,
        vaccine,
      ].any((d) => (d?['review_operations'] as List? ?? []).isNotEmpty);
      final status = loading
          ? 'Chargement des stocks'
          : error != null
          ? 'Stock à actualiser'
          : attention
          ? 'Une opération nécessite votre attention'
          : cachedStock
          ? 'Stock à actualiser'
          : uncertain
          ? 'Synchronisation en attente · niveau à vérifier'
          : levelLabel(value);
      return Tooltip(
        message: '${isFeed ? 'Aliments' : 'Vaccins'} : $status',
        child: Semantics(
          label: '${isFeed ? 'Aliments' : 'Vaccins'} : $status',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFeed ? Icons.shopping_bag_outlined : Icons.vaccines_outlined,
                size: 22,
                color: Colors.deepPurple,
              ),
              const SizedBox(width: 5),
              Container(
                key: Key(isFeed ? 'feed-level' : 'vaccine-level'),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: levelColor(value),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DashboardKpiCard(
      key: const Key('consumables-kpi'),
      title: 'Consommables',
      icon: Icons.category_outlined,
      color: Colors.deepPurple,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConsumablesScreen(
              api: widget.api,
              species: selectedSpecies,
              lot: selectedLot,
            ),
          ),
        );
        if (mounted) await load();
      },
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [level(true), const SizedBox(width: 22), level(false)],
          ),
          if ([
            feed,
            vaccine,
          ].any((d) => (d?['review_operations'] as List? ?? []).isNotEmpty))
            const Text(
              'À vérifier',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
        ],
      ),
    );
  }

  Widget trackingCard(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE4E8EC)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Stack(
      children: [
        Padding(padding: const EdgeInsets.all(18), child: child),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 3,
          child: ColoredBox(
            color: widget.trackingKind == true
                ? Colors.green
                : Colors.deepPurple,
          ),
        ),
      ],
    ),
  );

  List get stockLots => feed?['lots'] as List? ?? const [];
  String lotName(Object? id) {
    for (final row in stockLots) {
      if (row['id'] == id) return '${row['nom']}';
    }
    return 'Lot non renseigné';
  }

  String speciesName(Object? id) {
    for (final row in feed?['species'] as List? ?? const []) {
      if (row['id'] == id) return '${row['nom']}';
    }
    return 'Espèce non renseignée';
  }

  String day(Object? raw) {
    final value = DateTime.tryParse('$raw')?.toLocal();
    if (value == null) return 'Date indisponible';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  Widget filters() {
    final speciesRows = feed?['species'] as List? ?? const [];
    final lots = [
      for (final l in stockLots)
        if (selectedSpecies == null || l['espece_id'] == selectedSpecies) l,
    ];
    final speciesField = V2Field(child:DropdownButtonFormField<int>(
      key: ValueKey('consumables-species-$selectedSpecies'),
      initialValue: selectedSpecies,
      isExpanded: true,
      decoration: const V2InputDecoration(
        labelText: 'Espèce',
        prefixIcon: Icon(Icons.pets_outlined),),
      items: [
        const DropdownMenuItem<int>(
          value: null,
          child: Text('Toutes les espèces'),
        ),
        if (selectedSpecies != null &&
            !speciesRows.any((s) => s['id'] == selectedSpecies))
          DropdownMenuItem(
            value: selectedSpecies,
            child: Text(speciesName(selectedSpecies)),
          ),
        for (final s in speciesRows)
          DropdownMenuItem(value: s['id'] as int, child: Text('${s['nom']}')),
      ],
      onChanged: (id) => setState(() {
        selectedSpecies = id;
        selectedLot = null;
      }),
    ));
    final lotField = V2Field(child:DropdownButtonFormField<int>(
      key: ValueKey('consumables-lot-$selectedLot'),
      initialValue: selectedLot,
      isExpanded: true,
      decoration: const V2InputDecoration(
        labelText: 'Lot',
        prefixIcon: Icon(Icons.inventory_2_outlined),),
      items: [
        const DropdownMenuItem<int>(value: null, child: Text('Tous les lots')),
        if (selectedLot != null && !lots.any((l) => l['id'] == selectedLot))
          DropdownMenuItem(
            value: selectedLot,
            child: Text(lotName(selectedLot)),
          ),
        for (final l in lots)
          DropdownMenuItem(value: l['id'] as int, child: Text('${l['nom']}')),
      ],
      onChanged: (id) => setState(() => selectedLot = id),
    ));
    return trackingCard(
      LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 600
            ? Row(
                children: [
                  Expanded(child: speciesField),
                  const SizedBox(width: 16),
                  Expanded(child: lotField),
                ],
              )
            : Column(
                children: [speciesField, const SizedBox(height: 16), lotField],
              ),
      ),
    );
  }

  Future<void> withLot(Widget Function(int, String) builder) async {
    final captured = identity;
    int? id = selectedLot;
    if (id == null) {
      final lots = [
        for (final l in stockLots)
          if (selectedSpecies == null || l['espece_id'] == selectedSpecies) l,
      ];
      id = await showModalBottomSheet<int>(
        context: context,
        builder: (context) => _StockScope(
          allowed: () => current && identity == captured,
          changes: widget.api.sessionChanges,
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Choisir le lot concerné')),
                if (lots.isEmpty)
                  const ListTile(
                    title: Text('Aucun lot disponible pour cette espèce.'),
                  ),
                for (final l in lots)
                  ListTile(
                    title: Text('${l['nom']}'),
                    onTap: () => Navigator.pop(context, l['id'] as int),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (id == null || !mounted || !current || captured != identity) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => builder(id!, lotName(id))),
    );
    if (mounted && current) await load();
  }

  Future<void> allHistory(bool isFeed) async {
    final captured = identity;
    final products = (isFeed ? fs : vs)['details'] as List;
    final chosen = await showModalBottomSheet<Map>(
      context: context,
      builder: (context) => _StockScope(
        allowed: () => current && identity == captured,
        changes: widget.api.sessionChanges,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Choisir un produit')),
              if (products.isEmpty)
                const ListTile(title: Text('Aucun produit enregistré.')),
              for (final p in products)
                ListTile(
                  title: Text('${p['name']}'),
                  onTap: () => Navigator.pop(context, p as Map),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted && current && captured == identity)
      await history(chosen);
  }

  List relevantVials(Map data, Map product) {
    final rows = [
      for (final v in data['vials'] as List? ?? const [])
        if (v['product'] == product['id'] &&
            ((v['confirmed_physical'] ?? v['physical']) as num) > 0 &&
            (species == null || v['species'] == species) &&
            (selectedLot == null ||
                v['lot'] == null ||
                v['lot'] == selectedLot))
          v,
    ];
    rows.sort((a, b) => '${a['expires_on']}'.compareTo('${b['expires_on']}'));
    return rows;
  }

  Widget tracking() {
    final isFeed = widget.trackingKind!,
        sum = isFeed ? fs : vs,
        data = isFeed ? feed! : vaccine!;
    final products = sum['details'] as List;
    final pending = (data['pending_operations'] as List? ?? []).isNotEmpty;
    final review = (data['review_operations'] as List? ?? []).isNotEmpty;
    final health = [
      for (final t in tasks)
        if (t['health'] is Map &&
            t['health']['fulfilled'] != true &&
            t['status'] != 'CANCELLED' &&
            (species == null || t['health']['species'] == species) &&
            (selectedLot == null || t['health']['lot'] == selectedLot))
          t,
    ];
    health.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final recent = [
      for (final v in recentVaccinations)
        if ((selectedLot == null || v['lot'] == selectedLot) &&
            (species == null ||
                stockLots.any(
                  (l) => l['id'] == v['lot'] && l['espece_id'] == species,
                )))
          v,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filters(),
        trackingCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isFeed
                        ? Icons.shopping_bag_outlined
                        : Icons.vaccines_outlined,
                    color: isFeed ? Colors.green : Colors.deepPurple,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isFeed
                          ? 'Stock d’aliments disponible'
                          : 'Doses utilisables',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isFeed
                    ? '${consumableQuantity(sum['confirmed'])} kg'
                    : '${sum['usable']} doses',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (!isFeed) Text('${sum['vials']} flacons disponibles'),
              if (pending || data['local_estimate'] == true)
                Text(
                  isFeed
                      ? 'Estimation après opérations en attente : ${consumableQuantity(sum['estimated'])} kg'
                      : 'Estimation après opérations en attente : ${sum['estimated']} doses',
                ),
              Text(state(data)),
              if (review)
                const Text(
                  'Une opération nécessite votre attention.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              if (num.tryParse('${sum['estimated']}') case final n? when n < 0)
                const Text(
                  'Stock à actualiser : vérifiez les opérations en attente.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              if (selectedLot != null)
                const Text(
                  'Inclut le stock partagé de l’espèce et le stock réservé à ce lot.',
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (rights!.allows('expenses.create'))
              FilledButton.icon(
                key: const Key('consumable-purchase'),
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(
                  isFeed ? 'Acheter un aliment' : 'Acheter un vaccin',
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddDepenseScreen(
                        apiService: widget.api,
                        procurementKind: isFeed ? 'FEED' : 'VACCINE',
                      ),
                    ),
                  );
                  if (mounted && current) await load();
                },
              ),
            if (rights!.allows(isFeed ? 'feed.create' : 'vaccinations.create'))
              OutlinedButton.icon(
                key: const Key('consumable-record'),
                icon: Icon(
                  isFeed ? Icons.outbox_outlined : Icons.vaccines_outlined,
                ),
                label: Text(
                  isFeed
                      ? 'Enregistrer une distribution'
                      : 'Enregistrer une vaccination',
                ),
                onPressed: () => withLot(
                  (id, name) => isFeed
                      ? FeedDistributionFormScreen(
                          apiService: widget.api,
                          lotId: id,
                          lotName: name,
                        )
                      : VaccinationForm(api: widget.api, lotId: id),
                ),
              ),
            OutlinedButton.icon(
              key: const Key('consumable-history'),
              icon: const Icon(Icons.history),
              label: const Text('Consulter l’historique'),
              onPressed: () => allHistory(isFeed),
            ),
            OutlinedButton.icon(
              onPressed: () => details(isFeed),
              icon: const Icon(Icons.info_outline),
              label: const Text('Détails du stock'),
            ),
            if (!isFeed && rights!.allows('agenda.read'))
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: const Text('Rappels sanitaires'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        HealthAgendaScreen(api: widget.api, lotId: selectedLot),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          isFeed ? 'Mes aliments' : 'Mes vaccins',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          trackingCard(
            Text(
              isFeed
                  ? 'Aucun aliment enregistré. Ajoutez un achat pour commencer.'
                  : 'Aucun vaccin enregistré. Ajoutez un achat pour commencer.',
            ),
          ),
        for (final p in products)
          trackingCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['name']}${p['archived'] == true ? ' · archivé' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isFeed
                      ? '${consumableQuantity(p['confirmed'])} kg disponibles'
                      : '${p['usable']} doses utilisables · ${p['vials']} flacons disponibles',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (pending || data['local_estimate'] == true)
                  Text(
                    isFeed
                        ? 'Estimation : ${consumableQuantity(p['estimated'])} kg'
                        : 'Estimation : ${p['estimated']} doses',
                  ),
                if (p['archived'] != true &&
                    num.tryParse('${p[isFeed ? 'confirmed' : 'usable']}') == 0)
                  const Text(
                    'Stock épuisé',
                    style: TextStyle(color: Colors.red),
                  ),
                if (p['low'] == true &&
                    p['archived'] != true &&
                    num.tryParse('${p[isFeed ? 'confirmed' : 'usable']}') != 0)
                  const Text(
                    'Stock faible',
                    style: TextStyle(color: Colors.orange),
                  ),
                if (isFeed)
                  for (final pos in p['positions'] as List? ?? const [])
                    if ((species == null || pos['species_id'] == species) &&
                        (selectedLot == null ||
                            pos['lot_id'] == null ||
                            pos['lot_id'] == selectedLot))
                      Text(
                        '${speciesName(pos['species_id'])} · ${pos['lot_id'] == null ? 'Stock partagé' : lotName(pos['lot_id'])} : ${consumableQuantity(pos['kg'])} kg',
                      ),
                if (!isFeed)
                  for (final vial in relevantVials(data, p).take(3))
                    Text(
                      '${speciesName(vial['species'])} · ${vial['lot'] == null ? 'Stock partagé' : lotName(vial['lot'])} · Péremption : ${day(vial['expires_on'])}',
                    ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => history(p),
                      child: const Text('Historique'),
                    ),
                    if (rights!.role == 'OWNER')
                      TextButton(
                        onPressed: () => threshold(p, isFeed),
                        child: const Text('Configurer le seuil'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (!isFeed) ...[
          Text(
            'Vaccinations et prochaines échéances',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (rights!.allows('vaccinations.read')) ...[
            if (recentUnavailable)
              const Text('Vaccinations récentes à actualiser.'),
            if (!recentUnavailable && recent.isEmpty)
              const Text('Aucune vaccination récente pour cette sélection.'),
            for (final v in recent.take(5))
              ListTile(
                leading: const Icon(
                  Icons.vaccines_outlined,
                  color: Colors.deepPurple,
                ),
                title: Text(
                  '${v['vaccine']}${v['voided'] == true ? ' · annulée' : ''}',
                ),
                subtitle: Text(
                  '${day(v['vaccinated_at'])} · ${lotName(v['lot'])}${v['local_only'] == true ? ' · Synchronisation en attente' : ''}',
                ),
              ),
          ],
          if (agendaUnavailable) const Text('Agenda à actualiser.'),
          if (health.isEmpty)
            const Text('Aucune échéance sanitaire pour cette sélection.'),
          for (final t in health.take(5))
            ListTile(
              leading: Icon(
                Icons.event,
                color: healthTaskOverdue(t, DateTime.now().toUtc())
                    ? Colors.deepOrange
                    : Colors.deepPurple,
              ),
              title: Text('${t['title']}'),
              subtitle: Text(
                '${day(t['date'])}${healthTaskOverdue(t, DateTime.now().toUtc()) ? ' · En retard' : ''}',
              ),
            ),
          if (rights!.allows('vaccinations.read'))
            TextButton.icon(
              onPressed: () => withLot(
                (id, name) => VaccinationScreen(
                  api: widget.api,
                  lotId: id,
                  lotName: name,
                ),
              ),
              icon: const Icon(Icons.history),
              label: const Text('Vaccinations récentes et historique du lot'),
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          children: [
            TextButton.icon(
              onPressed: settings,
              icon: const Icon(Icons.tune),
              label: const Text('Configurer les alertes'),
            ),
            TextButton.icon(
              onPressed: load,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return compactCard();
    if (loading)
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Chargement des stocks physiques…'),
      );
    if (error != null || !current)
      return ListTile(
        title: Text(error ?? 'Profil changé. Actualisez les stocks.'),
        trailing: IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
      );
    if (selectedLot != null && species == null)
      return const ListTile(
        title: Text(
          'Espèce du lot indisponible : actualisez les références avant de consulter le stock partagé.',
        ),
      );
    if (widget.trackingKind != null) return tracking();
    final now = DateTime.now().toUtc();
    var overdue = 0, upcoming = 0;
    for (final task in tasks) {
      final h = task['health'];
      if (h is! Map ||
          h['fulfilled'] == true ||
          task['status'] == 'CANCELLED' ||
          (widget.species != null && h['species'] != widget.species) ||
          (widget.lot != null && h['lot'] != widget.lot))
        continue;
      if (healthTaskOverdue(task, now)) {
        overdue++;
      } else if (upcomingDays != null) {
        final day = DateTime.tryParse('${task['date']}');
        if (day != null &&
            !day.isAfter(parisDay(now).add(Duration(days: upcomingDays!))))
          upcoming++;
      }
    }
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 650
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: card(true)),
                    Expanded(child: card(false)),
                  ],
                )
              : Column(children: [card(true), card(false)]),
        ),
        if (agendaUnavailable)
          const Text(
            'Agenda indisponible : les alertes vaccinales n’ont pas pu être actualisées.',
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (overdue > 0 || upcoming > 0)
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        HealthAgendaScreen(api: widget.api, lotId: widget.lot),
                  ),
                ),
                child: Text(
                  '$upcoming vaccinations à venir · $overdue en retard',
                ),
              ),
            TextButton(
              onPressed: settings,
              child: const Text('Configurer les alertes visuelles'),
            ),
            IconButton(
              onPressed: load,
              tooltip: 'Actualiser les stocks',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }
}

class _StockScope extends StatefulWidget {
  const _StockScope({required this.allowed, required this.child, this.changes});
  final bool Function() allowed;
  final Widget child;
  final Listenable? changes;
  @override
  State<_StockScope> createState() => _StockScopeState();
}

class _StockScopeState extends State<_StockScope> {
  Timer? timer;
  bool valid = true;
  void check() {
    final next = widget.allowed();
    if (mounted && next != valid) setState(() => valid = next);
  }

  @override
  void initState() {
    super.initState();
    valid = widget.allowed();
    widget.changes?.addListener(check);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => check());
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.changes?.removeListener(check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => valid
      ? widget.child
      : const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Profil ou droits modifiés. Fermez cette vue puis actualisez.',
            ),
          ),
        );
}

String movementLabel(Object? kind) =>
    const {
      'ENTRY': 'Entrée',
      'DISTRIBUTION': 'Distribution',
      'TRANSFER': 'Transfert',
      'LOSS': 'Perte',
      'CORRECTION': 'Correction',
      'ADMINISTRATION': 'Administration',
      'REVERSAL': 'Annulation',
    }[kind] ??
    'Mouvement';

class ConsumablesScreen extends StatelessWidget {
  const ConsumablesScreen({
    super.key,
    required this.api,
    this.species,
    this.lot,
  });
  final ApiService api;
  final int? species, lot;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Suivi des consommables')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, c) {
              Widget option(bool feed) => Card(
                color: Colors.white,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Key(feed ? 'consumables-food' : 'consumables-vaccines'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConsumableTrackingScreen(
                        api: api,
                        isFeed: feed,
                        species: species,
                        lot: lot,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          feed
                              ? Icons.shopping_bag_outlined
                              : Icons.vaccines_outlined,
                          size: 42,
                          color: feed ? Colors.green : Colors.deepPurple,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          feed ? 'Suivi des aliments' : 'Suivi des vaccins',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          feed
                              ? 'Stocks, achats et distributions'
                              : 'Stocks, vaccinations et péremptions',
                        ),
                        const SizedBox(height: 20),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              return c.maxWidth >= 650
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: option(true)),
                        const SizedBox(width: 16),
                        Expanded(child: option(false)),
                      ],
                    )
                  : Column(
                      children: [
                        option(true),
                        const SizedBox(height: 16),
                        option(false),
                      ],
                    );
            },
          ),
        ),
      ),
    ),
  );
}

class ConsumableTrackingScreen extends StatelessWidget {
  const ConsumableTrackingScreen({
    super.key,
    required this.api,
    required this.isFeed,
    this.species,
    this.lot,
  });
  final ApiService api;
  final bool isFeed;
  final int? species, lot;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(isFeed ? 'Suivi des aliments' : 'Suivi des vaccins'),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: PhysicalStockCards(
            api: api,
            species: species,
            lot: lot,
            trackingKind: isFeed,
          ),
        ),
      ),
    ),
  );
}
