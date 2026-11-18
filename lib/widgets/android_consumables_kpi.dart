import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/farmer_runtime.dart';
import '../services/farm_session.dart';
import '../services/physical_stock_summary.dart';
import 'dashboard_kpi_card.dart';

/// Matches the published compact card using only the qualified Android reads.
/// Tablet stock projections and write workflows need separate qualification.
class AndroidConsumablesKpi extends StatefulWidget {
  const AndroidConsumablesKpi({
    super.key,
    required this.api,
    this.session,
    required this.sessionIdentity,
    this.species,
    this.lot,
    required this.revision,
  });
  final ApiService api;
  final FarmSession? session;
  final String? sessionIdentity;
  final int? species, lot;
  final int revision;
  @override
  State<AndroidConsumablesKpi> createState() => _AndroidConsumablesKpiState();
}

class _AndroidConsumablesKpiState extends State<AndroidConsumablesKpi> {
  Map? feed, vaccine;
  String? identity;
  int generation = 0;
  bool loading = false;
  Timer? clock;
  bool get allowed =>
      widget.api is! FarmerApiService &&
      widget.sessionIdentity != null &&
      widget.sessionIdentity == ApiService.sessionIdentity &&
      widget.session?.permissions?.allows('stocks.read') == true;
  bool get current =>
      allowed && identity != null && identity == ApiService.sessionIdentity;
  @override
  void initState() {
    super.initState();
    load();
    widget.api.sessionChanges?.addListener(changed);
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void changed() {
    if (mounted) load();
  }

  @override
  void dispose() {
    clock?.cancel();
    widget.api.sessionChanges?.removeListener(changed);
    super.dispose();
  }

  @override
  void didUpdateWidget(AndroidConsumablesKpi old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api) {
      old.api.sessionChanges?.removeListener(changed);
      widget.api.sessionChanges?.addListener(changed);
    }
    if (old.revision != widget.revision ||
        old.sessionIdentity != widget.sessionIdentity ||
        old.session != widget.session ||
        old.api != widget.api ||
        old.species != widget.species ||
        old.lot != widget.lot) {
      load();
    }
  }

  Future<void> load() async {
    final ticket = ++generation, captured = ApiService.sessionIdentity;
    setState(() {
      feed = null;
      vaccine = null;
      identity = null;
      loading = allowed;
    });
    if (!allowed || captured == null) return;
    try {
      final values = await Future.wait([
        widget.api.get('/feed-supplies/?presentation=1'),
        widget.api.get('/vaccine-supplies/'),
      ]);
      if (!mounted || ticket != generation) return;
      if (captured != ApiService.sessionIdentity || !allowed) {
        setState(() => loading = false);
        return;
      }
      for (final v in values) {
        if (v is! Map ||
            v['exploitation'] != widget.session!.farmId ||
            v['products'] is! List) {
          throw StateError('Invalid farm scope');
        }
      }
      if (values[1]['vials'] is! List) {
        throw StateError('Invalid vaccine snapshot');
      }
      feedSummary(values[0] as Map, species: widget.species, lot: widget.lot);
      vaccineSummary(
        values[1] as Map,
        DateTime.now().toUtc(),
        species: widget.species,
        lot: widget.lot,
      );
      setState(() {
        feed = values[0] as Map;
        vaccine = values[1] as Map;
        identity = captured;
        loading = false;
      });
    } catch (_) {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  bool get uncertain => [feed, vaccine].any(
    (d) =>
        d?['as_of'] == null ||
        d?['local_estimate'] == true ||
        (d?['pending_operations'] as List? ?? const []).isNotEmpty ||
        (d?['review_operations'] as List? ?? const []).isNotEmpty,
  );
  Widget level(bool isFeed) {
    final ready = current && feed != null && vaccine != null;
    final sum = ready
        ? (isFeed
              ? feedSummary(feed!, species: widget.species, lot: widget.lot)
              : vaccineSummary(
                  vaccine!,
                  DateTime.now().toUtc(),
                  species: widget.species,
                  lot: widget.lot,
                ))
        : null;
    final value = ready
        ? consumableLevel(
            sum!['details'] as List,
            feed: isFeed,
            filtered: widget.species != null || widget.lot != null,
            uncertain: uncertain,
          )
        : ConsumableLevel.neutral;
    final status = loading
        ? 'Chargement des stocks'
        : !ready
        ? 'Stock à actualiser'
        : uncertain
        ? 'Synchronisation en attente · niveau à vérifier'
        : levelLabel(value);
    final label = '${isFeed ? 'Aliments' : 'Vaccins'} : $status';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
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

  void details() {
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) =>
      _ConsumablesDetails(source: this)));
  }

  @override
  Widget build(BuildContext context) => DashboardKpiCard(
    key: const Key('consumables-kpi'),
    title: 'Consommables',
    icon: Icons.category_outlined,
    color: Colors.deepPurple,
    onTap: details,
    content: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [level(true), const SizedBox(width: 22), level(false)],
    ),
  );
}

/// Read-only server details. No cache, projection, write command or permission extension.
class _ConsumablesDetails extends StatefulWidget {
  const _ConsumablesDetails({required this.source});
  final _AndroidConsumablesKpiState source;
  @override
  State<_ConsumablesDetails> createState() => _ConsumablesDetailsState();
}
class _ConsumablesDetailsState extends State<_ConsumablesDetails> {
  bool isFeed = true;
  Timer? clock;
  @override
  void initState() {
    super.initState();
    widget.source.widget.api.sessionChanges?.addListener(changed);
    clock = Timer.periodic(const Duration(seconds: 1), (_) => changed());
  }
  void changed() { if (mounted) setState(() {}); }
  @override
  void dispose() {
    clock?.cancel();
    widget.source.widget.api.sessionChanges?.removeListener(changed);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final valid = source.mounted && source.current;
    final data = valid ? (isFeed ? source.feed : source.vaccine) : null;
    final summary = data == null ? null : isFeed
      ? feedSummary(data, species:source.widget.species,lot:source.widget.lot)
      : vaccineSummary(data,DateTime.now().toUtc(),species:source.widget.species,lot:source.widget.lot);
    return Scaffold(
      appBar: AppBar(title: const Text('Consommables')),
      body: ListView(padding:const EdgeInsets.all(24),children:[
        Wrap(spacing:12,children:[
          ChoiceChip(label:const Text('Aliments'),selected:isFeed,onSelected:(_)=>setState(()=>isFeed=true)),
          ChoiceChip(label:const Text('Vaccins'),selected:!isFeed,onSelected:(_)=>setState(()=>isFeed=false)),
        ]),
        const SizedBox(height:16),
        if(summary==null) const Text('Stocks indisponibles. Actualisez le tableau de bord avec une session autorisée.')
        else ...[
          Text('Lecture serveur · ${data!['as_of'] ?? 'fraîcheur inconnue'}'),
          if(source.widget.species!=null || source.widget.lot!=null)
            const Text('Périmètre filtré : les seuils globaux ne sont pas appliqués.'),
          if(source.uncertain) const Text('Opérations en attente ou en revue, estimation ou fraîcheur inconnue : niveau à vérifier.'),
          for(final row in summary['details'] as List) Card(child:Padding(
            padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('${row['name'] ?? row['nom'] ?? 'Produit ${row['id']}'}',style:Theme.of(context).textTheme.titleMedium),
              if(isFeed) ...[
                Text("Confirmé : ${row['confirmed']} kg"),
                Text("Partagé : ${row['shared']} kg · Réservé : ${row['reserved']} kg"),
                Text("En attente : ${row['pending']} kg · Estimé : ${row['estimated']} kg"),
              ] else ...[
                Text("Physique : ${row['physical']} doses · Utilisable : ${row['usable']} doses"),
                Text("Périmé : ${row['expired']} doses · Inutilisable : ${row['unusable']} doses"),
                Text("Estimé : ${row['estimated']} doses · Flacons utilisables : ${row['vials']}"),
              ],
              if(row['low']==true && !source.uncertain) const Text('Seuil de stock atteint'),
            ]))),
          if((summary['details'] as List).isEmpty) const Text('Aucun produit dans cet instantané.'),
        ],
        const SizedBox(height:16),
        const Text('Achats, distributions, vaccinations, historique et réglage des alertes depuis ce suivi : adaptation Android non disponible. Aucune opération ne peut être enregistrée ici.'),
      ]),
    );
  }
}
