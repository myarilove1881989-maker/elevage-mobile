import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';

const cycleFinancialLabels = <String, String>{
  'revenue': 'Ventes',
  'animal_purchases': 'Achats d’animaux',
  'expenses': 'Dépenses enregistrées',
  'charges': 'Total des charges enregistrées',
  'result': 'Résultat enregistré',
  'result_percent': 'Taux de résultat',
  'allocated_payments_to_date': 'Règlements affectés à ce jour',
  'receivables_to_date': 'Créances à ce jour',
};
const cycleTechnicalLabels = <String, String>{
  'duration_days': 'Durée du cycle',
  'initial_animals': 'Effectif de départ documenté',
  'live_entries': 'Entrées vivantes documentées',
  'animals_sold': 'Animaux vendus',
  'deaths': 'Mortalités déclarées',
  'mortality_percent': 'Taux de mortalité sur entrées documentées',
  'remaining_animals': 'Effectif restant à la date de référence',
  'births': 'Naissances vivantes',
  'stillbirths': 'Mort-nés',
  'feed_kg': 'Aliments distribués',
  'vaccination_sessions': 'Séances de vaccination / pertes enregistrées',
  'administered_doses': 'Doses administrées',
  'lost_vaccine_doses': 'Doses perdues',
  'eggs_collected': 'Œufs collectés',
  'eggs_sold': 'Œufs vendus',
  'eggs_broken': 'Œufs cassés à la collecte',
  'current_egg_stock': 'Stock courant d’œufs',
  'mean_weight_kg': 'Dernier poids moyen de l’échantillon',
  'daily_gain_g': 'Croissance moyenne entre deux pesées',
};

String cycleValue(String key, dynamic value) {
  if (value == null) return 'Non calculable';
  final number = num.tryParse('$value');
  if (number == null) return 'Donnée indisponible';
  if (cycleFinancialLabels.containsKey(key) && !key.endsWith('_percent')) {
    return AppSettings.instance.formatMoney(number.toDouble(), decimals: 0);
  }
  final unit = key.endsWith('_percent')
      ? ' %'
      : key.endsWith('_kg')
      ? ' kg'
      : key == 'duration_days'
      ? ' jours'
      : key == 'daily_gain_g'
      ? ' g/j'
      : '';
  final digits = key.endsWith('_percent')
      ? 2
      : key.endsWith('_kg')
      ? 3
      : key == 'daily_gain_g'
      ? 2
      : 0;
  return '${number.toStringAsFixed(digits).replaceAll('.', ',')}$unit';
}

String _date(dynamic value) {
  final d = DateTime.tryParse('$value');
  return d == null
      ? 'date indisponible'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class CycleBalanceScreen extends StatefulWidget {
  const CycleBalanceScreen({super.key, required this.api, required this.lotId});
  final ApiService api;
  final int lotId;
  @override
  State<CycleBalanceScreen> createState() => _CycleBalanceScreenState();
}

class _CycleBalanceScreenState extends State<CycleBalanceScreen> {
  Map<String, dynamic>? data;
  int? compareId;
  int generation = 0;
  bool busy = true, cached = false;
  String? error;
  late final String? identity;
  @override
  void initState() {
    super.initState();
    identity = ApiService.sessionIdentity;
    ApiService.businessChanges.addListener(changed);
    ApiService.sessionExpired.addListener(changed);
    widget.api.sessionChanges?.addListener(changed);
    load();
  }

  void changed() {
    if (!mounted) return;
    if (identity != ApiService.sessionIdentity) {
      generation++;
      setState(() {
        data = null;
        busy = false;
        error = 'La session a changé. Rouvrez le bilan depuis le lot.';
      });
    } else {
      load();
    }
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.api.get(
        '/lots/${widget.lotId}/cycle-report/${compareId == null ? '' : '?compare=$compareId'}',
      );
      final wasCached = widget.api.lastReadWasCached;
      if (!mounted || request != generation) return;
      if (identity != ApiService.sessionIdentity) {
        changed();
        return;
      }
      final result = Map<String, dynamic>.from(value as Map);
      if (result['version'] != 1 ||
          (result['lot'] as Map?)?['id'] != widget.lotId) {
        throw StateError('Bilan invalide');
      }
      setState(() {
        data = result;
        cached = wasCached;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          data = null;
          error =
              'Bilan indisponible. Réessayez avec une connexion Internet ou ouvrez un bilan déjà préparé sur cet appareil.';
        });
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    ApiService.businessChanges.removeListener(changed);
    ApiService.sessionExpired.removeListener(changed);
    widget.api.sessionChanges?.removeListener(changed);
    super.dispose();
  }

  Widget section(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
      border: Border(bottom: BorderSide(color: color, width: 3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );

  Widget metric(String key, dynamic value, {String? label}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 20,
      runSpacing: 4,
      children: [
        Text(
          label ??
              cycleFinancialLabels[key] ??
              cycleTechnicalLabels[key] ??
              key,
        ),
        Text(
          cycleValue(key, value),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final d = data;
    final pending = widget.api.localOperations.any(
      (e) =>
          e.businessStatus != 'CONFIRMED' && e.businessStatus != 'SUPERSEDED',
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilan du cycle'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: busy && d == null
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    TextButton(onPressed: load, child: const Text('Réessayer')),
                  ],
                ),
              ),
            )
          : d == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (busy) const LinearProgressIndicator(),
                          Text(
                            '${d['lot']['name']}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            d['closed'] == true
                                ? 'Bilan de fin de cycle'
                                : 'Bilan provisoire',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('Du ${_date(d['start'])} au ${_date(d['end'])}'),
                          Text(
                            'Dernière actualisation : ${_date(d['generated_at'])}. Les corrections et réouvertures peuvent modifier ce bilan.',
                          ),
                          if (cached)
                            const Text(
                              'Données mémorisées : bilan provisoire à actualiser avec Internet.',
                              style: TextStyle(color: Colors.deepOrange),
                            ),
                          if (pending)
                            const Text(
                              'Des opérations restent à confirmer. Elles ne sont pas incluses dans ce bilan.',
                              style: TextStyle(color: Colors.deepOrange),
                            ),
                          const SizedBox(height: 20),
                          section(
                            'Résultat économique',
                            Icons.account_balance_wallet_outlined,
                            Colors.green,
                            [
                              for (final entry
                                  in (d['financial'] as Map).entries)
                                metric('${entry.key}', entry.value),
                              const Divider(),
                              const Text(
                                'Répartition des dépenses',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if ((d['expense_breakdown'] as List).isEmpty)
                                const Text(
                                  'Aucune dépense enregistrée sur la période.',
                                ),
                              for (final row in d['expense_breakdown'])
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    '${row['category']} : ${cycleValue('expenses', row['amount'])}',
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Text('${d['formula']}'),
                              const Text(
                                'Ce résultat ne garantit pas un bénéfice net. Les créances ne sont pas des encaissements.',
                              ),
                            ],
                          ),
                          section(
                            'Résultats d’élevage',
                            Icons.pets_outlined,
                            Colors.orange,
                            [
                              for (final entry
                                  in (d['technical'] as Map).entries)
                                metric('${entry.key}', entry.value),
                              const Text(
                                'Une absence de saisie ne signifie pas zéro. Les pesées décrivent un échantillon, pas le poids vendu.',
                              ),
                            ],
                          ),
                          section(
                            'Points à vérifier',
                            Icons.fact_check_outlined,
                            Colors.purple,
                            [
                              for (final warning in d['warnings'])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text('• $warning'),
                                ),
                              const Divider(),
                              const Text(
                                'Consommables utilisés — analyse séparée',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                {
                                      'documented':
                                          'Valorisation des mouvements documentés',
                                      'partial': 'Valorisation partielle',
                                      'unavailable':
                                          'Valorisation indisponible',
                                    }[d['valuation']['status']] ??
                                    'Valorisation indisponible',
                              ),
                              metric(
                                'expenses',
                                d['valuation']['feed_cost'],
                                label: 'Coût des aliments distribués',
                              ),
                              metric(
                                'expenses',
                                d['valuation']['vaccine_cost'],
                                label: 'Coût des doses administrées',
                              ),
                              metric(
                                'expenses',
                                d['valuation']['loss_cost'],
                                label: 'Coût des pertes documentées',
                              ),
                              metric(
                                'expenses',
                                d['valuation']['reserved_feed_remaining_cost'],
                                label:
                                    'Valeur du stock d’aliments réservé restant',
                              ),
                              metric(
                                'administered_doses',
                                d['valuation']['reserved_vaccine_doses_remaining'],
                                label: 'Doses réservées restantes',
                              ),
                              metric(
                                'administered_doses',
                                d['valuation']['reserved_expired_doses'],
                                label:
                                    'Dont doses périmées (date de référence)',
                              ),
                              Text('${d['valuation']['method']}'),
                              Text('${d['valuation']['explanation']}'),
                            ],
                          ),
                          section(
                            'Comparer deux cycles',
                            Icons.compare_arrows,
                            Colors.blue,
                            [
                              const Text(
                                'Choisissez un autre lot de même espèce et de même production. Les écarts sont calculés : ce cycle moins le cycle choisi.',
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                key: ValueKey('cycle-comparison-$compareId'),
                                initialValue: compareId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Cycle de référence',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  const DropdownMenuItem<int>(
                                    value: null,
                                    child: Text('Choisir un cycle'),
                                  ),
                                  for (final row in d['candidates'])
                                    DropdownMenuItem<int>(
                                      value: row['id'] as int,
                                      child: Text(
                                        '${row['nom']} · ${_date(row['date_debut'])}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: busy
                                    ? null
                                    : (value) {
                                        setState(() => compareId = value);
                                        load();
                                      },
                              ),
                              if ((d['candidates'] as List).isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text('Aucun autre cycle compatible.'),
                                ),
                              if (d['comparison'] != null) ...comparison(d),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> comparison(Map<String, dynamic> d) {
    final comparison = d['comparison'] as Map;
    final other = comparison['reference'] as Map;
    final metrics = <String, dynamic>{...d['financial'], ...d['technical']};
    final reference = <String, dynamic>{
      ...other['financial'],
      ...other['technical'],
    };
    return [
      const SizedBox(height: 12),
      Text(
        'Référence : ${other['lot']['name']} · ${other['closed'] == true ? 'clôturé' : 'provisoire'}',
      ),
      for (final w in comparison['warnings']) Text('$w'),
      for (final w in other['warnings'])
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Cycle de référence : $w'),
        ),
      const SizedBox(height: 12),
      for (final entry in metrics.entries)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEAEAEA))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cycleFinancialLabels[entry.key] ??
                    cycleTechnicalLabels[entry.key] ??
                    entry.key,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (_, size) {
                  final cells = [
                    Text('Ce cycle : ${cycleValue(entry.key, entry.value)}'),
                    Text(
                      'Référence : ${cycleValue(entry.key, reference[entry.key])}',
                    ),
                  ];
                  return size.maxWidth < 500
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: cells,
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [for (final c in cells) Expanded(child: c)],
                        );
                },
              ),
              Text(
                _difference(
                  entry.key,
                  comparison['differences'][entry.key] as Map,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  String _difference(String key, Map diff) {
    if (diff['absolute'] == null) return 'Écart non calculable';
    if (diff['unit'] == 'points') return 'Écart : ${diff['absolute']} points';
    final relative = diff['relative_percent'];
    return 'Écart : ${cycleValue(key, diff['absolute'])}${relative == null ? ' · variation relative non calculable' : ' · $relative %'}';
  }
}
