import 'package:flutter/material.dart';
import '../widgets/v2_components.dart';
import '../widgets/dashboard_kpi_card.dart';
import '../theme/design_system_v2.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';
import 'aquatic_forms.dart';
import 'observation_panel.dart';
import 'stock_panel.dart';
import 'feeding_panel.dart';
import 'health_panel.dart';
import 'breeding_panel.dart';
import 'commerce_panel.dart';
import 'finance_agenda_panel.dart';

class AquaticWorkspace extends StatefulWidget {
  const AquaticWorkspace({
    super.key,
    required this.service,
    required this.capabilities,
    this.onReturn,
  });
  final AquaticService service;
  final Map<String, dynamic> capabilities;
  final VoidCallback? onReturn;
  @override
  State<AquaticWorkspace> createState() => AquaticWorkspaceState();
}

class AquaticWorkspaceState extends State<AquaticWorkspace> {
  void showDashboard() {
    setState(() => page = 'dashboard');
    reload();
  }

  void showPage(String destination) {
    setState(() => page = destination);
  }

  int generation = 0;
  bool loading = true;
  String? error;
  Map<String, dynamic>? dashboard;
  List<Map<String, dynamic>> installations = [],
      cohorts = [],
      species = [],
      events = [];
  String page = 'dashboard';
  String? healthInstallation, healthCohort, healthAction;
  String? breedingInstallation, breedingCohort, breedingAction;
  String? commerceInstallation, commerceCohort, commerceAction;
  String? planningInstallation, planningCohort, planningAction;
  String? speciesFilter, installationFilter, cohortFilter;
  bool allows(String right) =>
      (widget.capabilities['write'] as List? ?? const []).contains(right);
  String label(dynamic value) =>
      {
        'HARVEST': 'Récolte',
        'HARVEST_REVERSAL': 'Annulation de récolte',
        'FRY_REVERSAL': 'Annulation d’entrée d’alevins',
        'ACTIVE': 'Actif',
        'INACTIVE': 'Inactif',
        'OPEN': 'En cours',
        'CLOSED': 'Clôturée',
        'INITIAL': 'Affectation initiale',
        'TRANSFER': 'Transfert',
        'PURCHASE': 'Achat déclaré',
        'HATCH': 'Alevinage',
        'TRANSFER_IN': 'Origine externe',
        'OTHER': 'Autre',
        'BASSIN': 'Bassin',
        'ETANG': 'Étang',
        'CAGE': 'Cage',
        'BAC': 'Bac',
      }[value] ??
      '$value';
  String date(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    return parsed == null
        ? '$value'
        : parsed.toLocal().toString().substring(0, 16);
  }

  String installationName(dynamic id) =>
      installations
          .where((i) => i['id'] == id)
          .map((i) => '${i['name']}')
          .firstOrNull ??
      'Installation';
  String eventLines(dynamic value) => (value as List? ?? [])
      .map(
        (line) =>
            '${line['delta_count'] > 0 ? '+' : ''}${line['delta_count']} poissons · ${installationName(line['installation'])}',
      )
      .join('\n');
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> reload() async {
    final epoch = ++generation;
    final identity = ApiService.sessionIdentity;
    setState(() {
      loading = true;
      error = null;
      dashboard = null;
    });
    try {
      final parts = <String, String>{
        'species': ?speciesFilter,
        'installation': ?installationFilter,
        'cohort': ?cohortFilter,
      };
      final query = Uri(queryParameters: parts).query;
      final result = await Future.wait<dynamic>([
        widget.service.read('dashboard/${query.isEmpty ? '' : '?$query'}'),
        widget.service.list('installations/'),
        widget.service.list('cohorts/'),
        widget.service.list('species/'),
        widget.service.list('events/'),
      ]);
      if (!mounted ||
          generation != epoch ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        dashboard = result[0] as Map<String, dynamic>;
        installations = result[1] as List<Map<String, dynamic>>;
        cohorts = result[2] as List<Map<String, dynamic>>;
        species = result[3] as List<Map<String, dynamic>>;
        events = result[4] as List<Map<String, dynamic>>;
        loading = false;
      });
    } catch (e) {
      if (!mounted ||
          generation != epoch ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        loading = false;
        if (e is ApiHttpException && (e.status == 401 || e.status == 403)) {
          installations = [];
          cohorts = [];
          species = [];
          events = [];
          speciesFilter = null;
          installationFilter = null;
          cohortFilter = null;
        }
        error = e is ApiHttpException
            ? 'Accès ou données refusés : ${e.message}'
            : 'Connexion indisponible. Aucune nouvelle opération piscicole ne peut être enregistrée hors ligne.';
      });
    }
  }

  Future<void> form(String kind, {Map<String, dynamic>? entity}) async {
    if (loading || error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Actualisez les données avec une connexion avant cette opération.',
          ),
        ),
      );
      return;
    }
    final permission = kind == 'installation'
        ? 'aquatic.installations.manage'
        : kind == 'transfer'
        ? 'aquatic.transfers.create'
        : 'aquatic.cohorts.manage';
    if (!allows(permission) ||
        (kind == 'onboarding' && !allows('aquatic.installations.manage'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cette opération n’est pas autorisée pour votre compte.',
          ),
        ),
      );
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AquaticForm(
          service: widget.service,
          kind: kind,
          installations: installations,
          cohorts: cohorts,
          species: species,
          entity: entity,
        ),
      ),
    );
    if (changed == true && mounted) await reload();
  }

  Widget action(String text, String kind, String permission) => OutlinedButton(
    onPressed:
        allows(permission) &&
            (kind != 'onboarding' || allows('aquatic.installations.manage')) &&
            error == null &&
            !loading
        ? () => form(kind)
        : null,
    child: Text(text),
  );
  Widget picker(
    String label,
    String? selected,
    List<Map<String, dynamic>> rows,
    String valueKey,
    ValueChanged<String?> change,
  ) => SizedBox(
    width: 260,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$selected'),
      initialValue: selected,
      decoration: V2InputDecoration(labelText: label),
      isExpanded: true,
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('Tous')),
        ...rows.map(
          (r) => DropdownMenuItem(
            value: '${r[valueKey]}',
            child: Text(
              '${r['name'] ?? r['code']}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: loading
          ? null
          : (value) {
              change(value);
              reload();
            },
    ),
  );
  Widget metric(String name, String title, IconData icon) {
    final value = (dashboard?['metrics'] as Map?)?[name] as Map?;
    final uncertain = value?['quality'] == 'UNRECONCILED';
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height:
                180 +
                (MediaQuery.textScalerOf(context).scale(16) / 16 - 1) * 100,
            child: DashboardKpiCard(
              title: title,
              icon: icon,
              color: V2Colors.green,
              content: Text(
                value?['value']?.toString() ?? 'Non disponible',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (uncertain) ...[
            const SizedBox(height: 6),
            const Text(
              'Brut non rapproché',
              style: TextStyle(fontSize: 14, color: V2Colors.navy),
            ),
            Text(
              'Plage ${value?['lower']} à ${value?['upper']}',
              style: const TextStyle(fontSize: 14, color: V2Colors.navy),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (loading) const LinearProgressIndicator(),
      Expanded(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pisciculture',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Text(
                  'Effectifs aquatiques séparés de l’élevage terrestre. Nouvelles opérations en ligne uniquement.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in {
                      'dashboard': 'Tableau de bord',
                      'installations': 'Installations',
                      'cohorts': 'Cohortes',
                      'history': 'Historique',
                      'weights': 'Pesées',
                      'water': 'Eau',
                      'rules': 'Règles',
                      'stock': 'Pertes et inventaires',
                      'feeding': 'Alimentation',
                      'health': 'Santé',
                      'breeding': 'Reproduction',
                      'commerce': 'Récoltes et ventes',
                      'finances': 'Finances',
                      'agenda': 'Agenda',
                    }.entries)
                      OutlinedButton(
                        onPressed: () => setState(() => page = p.key),
                        child: Text(p.value),
                      ),
                    IconButton(
                      onPressed: reload,
                      tooltip: 'Actualiser',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (page == 'dashboard') ...[
                  Wrap(
                    spacing: 16,
                    runSpacing: 20,
                    children: [
                      picker(
                        'Espèce',
                        speciesFilter,
                        species,
                        'species',
                        (v) => speciesFilter = v,
                      ),
                      picker(
                        'Installation',
                        installationFilter,
                        installations,
                        'id',
                        (v) => installationFilter = v,
                      ),
                      picker(
                        'Cohorte',
                        cohortFilter,
                        cohorts,
                        'id',
                        (v) => cohortFilter = v,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (dashboard != null)
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        metric('live_count', 'Poissons vivants', Icons.water),
                        metric(
                          'active_installations',
                          'Installations actives',
                          Icons.pool,
                        ),
                        metric(
                          'active_cohorts',
                          'Cohortes actives',
                          Icons.layers,
                        ),
                      ],
                    ),
                  if (dashboard?['unassigned_losses'] != null)
                    Text(
                      'Pertes à rapprocher : ${dashboard?['unassigned_losses']} · Crédits non affectés : ${dashboard?['unassigned_credits'] ?? 0}',
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      action(
                        'Premier démarrage',
                        'onboarding',
                        'aquatic.cohorts.manage',
                      ),
                      action(
                        'Créer une installation',
                        'installation',
                        'aquatic.installations.manage',
                      ),
                      action(
                        'Créer une cohorte',
                        'cohort',
                        'aquatic.cohorts.manage',
                      ),
                      action(
                        'Transférer des poissons',
                        'transfer',
                        'aquatic.transfers.create',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (cohorts.isEmpty && !loading)
                    const Text(
                      'Aucune cohorte. Commencez par une installation, une espèce et sa première affectation.',
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Répartition par espèce',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final row in (dashboard?['by_species'] as List? ?? []))
                    ListTile(
                      title: Text('${row['cohort__species__nom']}'),
                      trailing: Text(
                        '${row['count']} poissons${row['quality'] == 'UNRECONCILED' ? ' (brut non rapproché)' : ''}',
                      ),
                    ),
                  const Text(
                    'Répartition par installation',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final row
                      in (dashboard?['by_installation'] as List? ?? []))
                    ListTile(
                      title: Text('${row['installation__name']}'),
                      trailing: Text(
                        '${row['count']} poissons${row['quality'] == 'UNRECONCILED' ? ' (brut non rapproché)' : ''}',
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (dashboard?['feeding_unavailable_reason'] != null)
                    const Text(
                      'Alimentation par espèce : Données insuffisantes. Consultez les distributions par bassin ou cohorte dans Alimentation.',
                    ),
                  if (dashboard?['feeding_overview'] is Map)
                    feedingOverview(dashboard!['feeding_overview'] as Map),
                  const Text(
                    'Consultez Récoltes et ventes, Finances et Agenda pour les opérations et leur suivi.',
                  ),
                ],
                if (page == 'installations') ...[
                  action(
                    'Créer une installation',
                    'installation',
                    'aquatic.installations.manage',
                  ),
                  if (installations.isEmpty && !loading)
                    const Text('Aucune installation.'),
                  for (final row in installations)
                    Card(
                      child: ListTile(
                        title: Text('${row['name']} · ${row['code']}'),
                        subtitle: Text(
                          '${label(row['type'])} · ${label(row['status'])}\nCapacité : ${row['capacity'] ?? 'Non renseignée'} ${row['capacity_unit'] ?? ''}\n${row['location'] ?? ''}',
                        ),
                        isThreeLine: true,
                        onTap: () => detail('installation', row),
                        trailing: IconButton(
                          tooltip: 'Modifier',
                          onPressed: allows('aquatic.installations.manage')
                              ? () => form('installation', entity: row)
                              : null,
                          icon: const Icon(Icons.edit),
                        ),
                      ),
                    ),
                ],
                if (page == 'cohorts') ...[
                  action(
                    'Créer une cohorte',
                    'cohort',
                    'aquatic.cohorts.manage',
                  ),
                  if (cohorts.isEmpty && !loading)
                    const Text('Aucune cohorte.'),
                  for (final row in cohorts)
                    Card(
                      child: ListTile(
                        title: Text('${row['name']} · ${row['code']}'),
                        subtitle: Text(
                          '${row['gross_count']} poissons · ${label(row['status'])}',
                        ),
                        onTap: () => detail('cohort', row),
                        trailing: IconButton(
                          tooltip: 'Modifier',
                          onPressed: allows('aquatic.cohorts.manage')
                              ? () => form('cohort_edit', entity: row)
                              : null,
                          icon: const Icon(Icons.edit),
                        ),
                      ),
                    ),
                ],
                if (page == 'finances' || page == 'agenda')
                  FinanceAgendaPanel(
                    key: ValueKey(
                      '$page:$planningInstallation:$planningCohort:$planningAction',
                    ),
                    service: widget.service,
                    agenda: page == 'agenda',
                    owner: widget.capabilities['can_enable'] == true,
                    rights: List<String>.from([
                      ...widget.capabilities['write'] as List? ?? [],
                      ...widget.capabilities['finance_write'] as List? ?? [],
                    ]),
                    installations: installations,
                    cohorts: cohorts,
                    species: species
                        .map((x) => {'id': x['species'], 'name': x['name']})
                        .toList(),
                    initialInstallation: planningInstallation,
                    initialCohort: planningCohort,
                    initialAction: planningAction,
                    onChanged: reload,
                  ),
                if (page == 'commerce')
                  CommercePanel(
                    key: ValueKey(
                      '$commerceInstallation:$commerceCohort:$commerceAction',
                    ),
                    service: widget.service,
                    owner: widget.capabilities['can_enable'] == true,
                    rights: List<String>.from([
                      ...widget.capabilities['write'] as List? ?? [],
                      ...widget.capabilities['commerce_write'] as List? ?? [],
                    ]),
                    installations: installations,
                    cohorts: cohorts,
                    species: species
                        .map((x) => {'id': x['species'], 'name': x['name']})
                        .toList(),
                    initialInstallation: commerceInstallation,
                    initialCohort: commerceCohort,
                    initialAction: commerceAction,
                    onChanged: reload,
                  ),
                if (page == 'breeding')
                  BreedingPanel(
                    key: ValueKey(
                      '$breedingInstallation:$breedingCohort:$breedingAction',
                    ),
                    service: widget.service,
                    owner: widget.capabilities['can_enable'] == true,
                    rights: List<String>.from(
                      widget.capabilities['write'] as List? ?? [],
                    ),
                    installations: installations,
                    cohorts: cohorts,
                    species: [
                      for (final s in species)
                        {'id': '${s['species']}', 'name': s['name']},
                    ],
                    initialInstallation: breedingInstallation,
                    initialCohort: breedingCohort,
                    initialAction: breedingAction,
                    onChanged: reload,
                  ),
                if (page == 'health')
                  HealthPanel(
                    key: ValueKey(
                      '$healthInstallation:$healthCohort:$healthAction',
                    ),
                    service: widget.service,
                    owner: widget.capabilities['can_enable'] == true,
                    rights: List<String>.from(
                      widget.capabilities['write'] as List? ?? [],
                    ),
                    installations: installations,
                    cohorts: cohorts,
                    species: [
                      for (final s in species)
                        {'id': '${s['species']}', 'name': s['name']},
                    ],
                    initialInstallation: healthInstallation,
                    initialCohort: healthCohort,
                    initialAction: healthAction,
                  ),
                if (page == 'feeding')
                  FeedingPanel(
                    service: widget.service,
                    owner: widget.capabilities['can_enable'] == true,
                    rights: List<String>.from(
                      widget.capabilities['write'] as List? ?? [],
                    ),
                    installations: installations,
                    cohorts: cohorts,
                    onChanged: reload,
                  ),
                if (page == 'stock')
                  StockPanel(
                    service: widget.service,
                    owner: widget.capabilities['can_enable'] == true,
                    rights: List<String>.from(
                      widget.capabilities['write'] as List? ?? [],
                    ),
                    installations: installations,
                    cohorts: cohorts,
                    onChanged: reload,
                  ),
                if (['weights', 'water', 'rules'].contains(page))
                  ObservationPanel(
                    key: ValueKey(page),
                    service: widget.service,
                    kind: page == 'weights'
                        ? 'WEIGHT'
                        : page == 'water'
                        ? 'WATER'
                        : 'RULE',
                    rights: List<String>.from(
                      widget.capabilities['write'] as List? ?? [],
                    ),
                    installations: installations,
                    cohorts: cohorts,
                  ),
                if (page == 'history') ...[
                  const Text(
                    'Affectations et transferts — historique conservé',
                  ),
                  if (events.isEmpty && !loading)
                    const Text('Aucun événement.'),
                  for (final row in events)
                    Card(
                      child: ListTile(
                        title: Text('${label(row['type'])} · ${row['reason']}'),
                        subtitle: Text(
                          '${date(row['occurred_at'])}\nAuteur : ${row['actor_name'] ?? 'Utilisateur ${row['actor']}'}\n${eventLines(row['lines'])}',
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
  void openHealthFrom(
    BuildContext dialog,
    String kind,
    Map<String, dynamic> row,
    String? action,
  ) {
    Navigator.pop(dialog);
    setState(() {
      healthCohort = kind == 'cohort' ? '${row['id']}' : null;
      healthInstallation = kind == 'cohort' ? null : '${row['id']}';
      if (kind == 'cohort') {
        final positions = row['positions'] as List? ?? [];
        if (positions.length == 1) {
          healthInstallation = '${positions.first['installation']}';
        }
      }
      healthAction = action;
      page = 'health';
    });
  }

  void openPlanningFrom(
    BuildContext dialog,
    String kind,
    Map<String, dynamic> row,
    bool agenda,
  ) {
    Navigator.pop(dialog);
    setState(() {
      planningCohort = kind == 'cohort' ? '${row['id']}' : null;
      planningInstallation = kind == 'cohort' ? null : '${row['id']}';
      if (kind == 'cohort') {
        final positions = row['positions'] as List? ?? [];
        if (positions.length == 1) {
          planningInstallation = '${positions.first['installation']}';
        }
      }
      planningAction = agenda ? 'TASK' : null;
      page = agenda ? 'agenda' : 'finances';
    });
  }

  void openCommerceFrom(
    BuildContext dialog,
    String kind,
    Map<String, dynamic> row,
  ) {
    Navigator.pop(dialog);
    setState(() {
      commerceCohort = kind == 'cohort' ? '${row['id']}' : null;
      commerceInstallation = kind == 'cohort' ? null : '${row['id']}';
      if (kind == 'cohort') {
        final positions = row['positions'] as List? ?? [];
        if (positions.length == 1) {
          commerceInstallation = '${positions.first['installation']}';
        }
      }
      commerceAction = 'HARVEST';
      page = 'commerce';
    });
  }

  void openBreedingFrom(
    BuildContext dialog,
    String kind,
    Map<String, dynamic> row,
  ) {
    Navigator.pop(dialog);
    setState(() {
      breedingCohort = kind == 'cohort' ? '${row['id']}' : null;
      breedingInstallation = kind == 'cohort' ? null : '${row['id']}';
      if (kind == 'cohort') {
        final positions = row['positions'] as List? ?? [];
        if (positions.length == 1) {
          breedingInstallation = '${positions.first['installation']}';
        }
      }
      breedingAction = 'GROUP';
      page = 'breeding';
    });
  }

  Future<void> detail(String kind, Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (c) => V2AlertDialog(
        title: Text('${row['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Code : ${row['code']} · Statut : ${label(row['status'])}'),
              if (kind == 'cohort') ...[
                Text(
                  'Origine : ${label((row['origin'] as Map)['type'])} · Début : ${date(row['started_at'])}',
                ),
                Text(
                  'Espèce : ${row['species_name'] ?? species.where((s) => s['species'] == row['species']).map((s) => s['name']).firstOrNull ?? 'Non renseignée'} · Stade : ${row['stage_name'] ?? 'Non renseigné'}',
                ),
                Text('Effectif total : ${row['gross_count']} poissons'),
                for (final p in row['positions'] as List)
                  Text(
                    '${installations.where((i) => i['id'] == p['installation']).map((i) => i['name']).firstOrNull ?? p['installation']} : ${p['gross_count']} poissons · disponibles ${p['available_count']}',
                  ),
              ] else ...[
                Text(
                  'Type : ${label(row['type'])} · Localisation : ${row['location']}',
                ),
                for (final cohort in cohorts)
                  for (final p in cohort['positions'] as List)
                    if (p['installation'] == row['id'])
                      Text('${cohort['name']} : ${p['gross_count']} poissons'),
              ],
              const SizedBox(height: 12),
              const Text(
                'Pesées et eau : historiques dans les onglets dédiés. Alimentation : stock et distributions dans l’onglet dédié.',
              ),
            ],
          ),
        ),
        actions: [
          if (allows('aquatic.agenda.plan'))
            TextButton.icon(
              onPressed: () => openPlanningFrom(c, kind, row, true),
              icon: const Icon(Icons.event, color: V2Colors.green),
              label: const Text('Planifier'),
            ),
          TextButton.icon(
            onPressed: () => openPlanningFrom(c, kind, row, false),
            icon: const Icon(
              Icons.account_balance_wallet,
              color: V2Colors.green,
            ),
            label: const Text('Finances'),
          ),
          if (allows('aquatic.harvest.create'))
            OutlinedButton.icon(
              onPressed: () => openCommerceFrom(c, kind, row),
              icon: const Icon(Icons.set_meal, color: Colors.green),
              label: const Text('Récolter'),
            ),
          if (allows('aquatic.breeders.manage'))
            TextButton.icon(
              onPressed: () => openBreedingFrom(c, kind, row),
              icon: const Icon(Icons.groups, color: V2Colors.green),
              label: const Text('Groupe de géniteurs'),
            ),
          if (allows('aquatic.health.observe'))
            TextButton.icon(
              onPressed: () => openHealthFrom(c, kind, row, 'OBSERVATION'),
              icon: const Icon(Icons.health_and_safety, color: V2Colors.green),
              label: const Text('Signaler un problème'),
            ),
          if (allows('aquatic.health.treat'))
            TextButton.icon(
              onPressed: () => openHealthFrom(c, kind, row, 'TREATMENT'),
              icon: const Icon(Icons.medical_services, color: V2Colors.green),
              label: const Text('Enregistrer un traitement'),
            ),
          TextButton(
            onPressed: () => openHealthFrom(c, kind, row, 'HISTORY'),
            child: const Text('Historique sanitaire'),
          ),

          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}
