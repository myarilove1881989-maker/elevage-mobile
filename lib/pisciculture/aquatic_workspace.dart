import 'aquatic_revenue_screen.dart';
import 'aquatic_expense_screen.dart';
import 'aquatic_clients_screen.dart';
import 'aquatic_dashboard_agenda.dart';
import 'aquatic_navigation.dart';
import 'package:flutter/material.dart';
import '../widgets/v2_components.dart';
import '../widgets/dashboard_kpi_card.dart';
import '../widgets/dashboard_metric_grid.dart';
import '../services/app_settings.dart';
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
    this.farmName = '',
  });
  final AquaticService service;
  final Map<String, dynamic> capabilities;
  final VoidCallback? onReturn;
  final String farmName;
  @override
  State<AquaticWorkspace> createState() => AquaticWorkspaceState();
}

class AquaticWorkspaceState extends State<AquaticWorkspace> {
  final List<String> pageHistory = [];
  void goBack() {
    if(pageHistory.isEmpty){showDashboard();return;}
    showPage(pageHistory.removeLast(),remember:false);
  }

  void showDashboard() {
    pageHistory.clear();
    setState(() => page = 'dashboard');
    reload();
  }

  void showPage(String destination, {bool remember=true}) {
    if (destination == 'purchases_hub') {
      form('cohort');
      return;
    }
    setState(() {
      if(remember && destination!=page) pageHistory.add(page);
      page = destination;
      healthInstallation = breedingInstallation = commerceInstallation =
          planningInstallation = installationFilter;
      healthCohort = breedingCohort = commerceCohort = planningCohort =
          cohortFilter;
      commerceAction = planningAction = stockAction = feedingAction = null;
      commerceSection = 'stock';
      planningSection = 'summary';
    });
  }

  void openMenu(AquaticMenuEntry entry) {
    final target = entry.destination;
    if (target == 'purchases_hub') {
      form('cohort');
      return;
    }
    if (target == 'new_cohort') {
      form('cohort');
      return;
    }
    if(['commerce_clients','commerce_balances'].contains(target)){financialDetail(target=='commerce_clients'?'customers':'clients');return;}
    if (target == 'transfer_form') {
      form('transfer');
      return;
    }
    showPage(target);
    setState(() {
      if (target == 'new_expense') {
        page = 'finances';
        planningSection = 'expenses';
        if (allows('expenses.create')) planningAction = 'EXPENSE';
      }
      if (target == 'feed_purchases') {
        page = 'feeding';
        if (allows('aquatic.feed.purchase')) feedingAction = 'PURCHASE';
      }
      if (target == 'stock_inventory') {
        page = 'stock';
        if (widget.capabilities['can_enable'] == true)
          stockAction = 'INVENTORY';
      }
      if (target == 'commerce_sale') {
        page = 'commerce';
        if (allows('aquatic.sales.create')) commerceAction = 'SALE';
      }
      if ([
        'commerce_clients',
        'commerce_invoices',
        'commerce_payments',
        'commerce_balances',
      ].contains(target)) {
        page = 'commerce';
        commerceSection = target.substring('commerce_'.length);
      }
      if (target == 'finance_revenues') {
        page = 'finances';
        planningSection = 'revenues';
      }
      if (target == 'finance_summary') {
        page = 'finances';
        planningSection = 'summary';
      }
    });
  }

  Widget menuHub(List<AquaticMenuEntry> entries) => LayoutBuilder(
    builder: (context, box) => Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final entry in entries)
          SizedBox(
            width: box.maxWidth < 280 ? box.maxWidth : 280,
            height:
                190 *
                (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(
                  1.0,
                  2.5,
                ),
            child: DashboardKpiCard(
              title: entry.title,
              icon: entry.icon,
              color: V2Colors.green,
              onTap: loading ? null : () => openMenu(entry),
              content: const Icon(Icons.arrow_forward, color: V2Colors.navy),
            ),
          ),
      ],
    ),
  );

  int generation = 0;
  bool loading = true;
  String? error;
  Map<String, dynamic>? dashboard, financialSummary;
  String? financeError;
  List<Map<String, dynamic>> installations = [],
      cohorts = [],
      species = [],
      events = [];
  String page = 'dashboard';
  String commerceSection = 'stock', planningSection = 'summary';
  String? stockAction, feedingAction;
  String? healthInstallation, healthCohort, healthAction;
  String? breedingInstallation, breedingCohort, breedingAction;
  String? commerceInstallation, commerceCohort, commerceAction;
  String? planningInstallation, planningCohort, planningAction;
  String? speciesFilter, installationFilter, cohortFilter;
  bool allows(String right) => [
    ...widget.capabilities['write'] as List? ?? const [],
    ...widget.capabilities['finance_write'] as List? ?? const [],
    ...widget.capabilities['commerce_write'] as List? ?? const [],
  ].contains(right);
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
      financialSummary = null;
      financeError = null;
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
        widget.service
            .read(
              'finance-summary/?${Uri(queryParameters: {...parts, 'from': DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10), 'to': DateTime.now().toIso8601String().substring(0, 10)}).query}',
            )
            .then<Map<String, dynamic>>((value) => value)
            .catchError((Object e) => <String, dynamic>{'_unavailable': true}),
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
        final finance = result[5] as Map<String, dynamic>;
        if (finance['_unavailable'] == true) {
          financeError = 'Indisponible';
        } else {
          financialSummary = finance;
        }
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
    if (changed == true && mounted) {
      await reload();
      if(mounted && ['cohort','installation'].contains(kind))ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:const Text('Enregistré'),action:SnackBarAction(label:kind=='cohort'?'Créer une autre cohorte':'Créer une autre installation',onPressed:()=>form(kind))));
    }
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
  Widget amount(Object? value, {bool money = false,Color color=V2Colors.navy}) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      value == null
          ? 'Indisponible'
          : money
          ? AppSettings.instance.formatMoney(value,decimals:RegExp(r'\.0+$').hasMatch('$value')?0:2)
          : '$value',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    ),
  );

  Map<String,String> get financialFilters=>{
    'species':?speciesFilter,'installation':?installationFilter,'cohort':?cohortFilter,
    'from':DateTime(DateTime.now().year,DateTime.now().month,1).toIso8601String().substring(0,10),
    'to':DateTime.now().toIso8601String().substring(0,10),
  };
  Future<void> financialDetail(String kind)async {
    final identity=ApiService.sessionIdentity;
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>kind=='revenue'?AquaticRevenueScreen(service:widget.service,filters:financialFilters,onHistory:(){if(!mounted)return;Navigator.pop(context);showPage('finances');setState(()=>planningSection='revenues');}):kind=='expenses'?AquaticExpenseScreen(service:widget.service,filters:financialFilters,onHistory:(){if(!mounted)return;Navigator.pop(context);showPage('finances');setState(()=>planningSection='expenses');},lotNom:cohorts.where((c)=>c['id']==cohortFilter).map((c)=>'${c['name']}').firstOrNull):AquaticClientsScreen(service:widget.service,filters:financialFilters,canPay:allows('cash.create'),includeAllClients:kind=='customers',canCreate:kind=='customers' && allows('clients.create'))));
    if(mounted && identity==ApiService.sessionIdentity)await reload();
  }

  Widget dashboardCards() {
    final metrics = dashboard?['metrics'] as Map? ?? {};
    Map metric(String key) => metrics[key] as Map? ?? {};
    final live = metric('live_count');
    Widget card(
      String title,
      IconData icon,
      Widget content,
      VoidCallback tap,
    ) => DashboardKpiCard(
      title: title,
      icon: icon,
      color: title == "Chiffre d'affaires"
          ? Colors.blue
          : title == 'Dépenses'
          ? Colors.orange
          : title == 'Solde clients'
          ? Colors.teal
          : V2Colors.green,
      contentHeight: title == 'Stock total' ? 72 : 56,
      content: content,
      onTap: loading || error != null ? null : tap,
    );
    return DashboardMetricGrid(
      children: [
        card(
          'Stock total',
          Icons.inventory_2,
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: amount(live['value'],color:V2Colors.green)),
              const Text('Poissons vivants', style: TextStyle(fontSize: 12,height:1)),
              Text("Installations actives : ${metric('active_installations')['value'] ?? '—'}",style:const TextStyle(fontSize:12,height:1)),
              Text("Cohortes actives : ${metric('active_cohorts')['value'] ?? '—'}",style:const TextStyle(fontSize:12,height:1)),
            ],
          ),
          () => showPage('stock_detail'),
        ),
        card(
          "Chiffre d'affaires",
          Icons.trending_up,
          amount(financialSummary?['billed_revenue'], money: true,color:Colors.blue),
          () => financialDetail('revenue'),
        ),
        card(
          'Dépenses',
          Icons.account_balance_wallet,
          amount(financialSummary?['aquatic_expenses'], money: true,color:Colors.orange),
          () => financialDetail('expenses'),
        ),
        card(
          'Solde clients',
          Icons.credit_card,
          amount(financialSummary?['client_balance_as_of'], money: true,color:Colors.teal),
          () => financialDetail('clients'),
        ),
        card(
          'Gestion',
          Icons.category_outlined,
          Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
            IconButton(tooltip:'Alimentation',onPressed:loading?null:()=>showPage('feeding'),icon:const Icon(Icons.grass_outlined,color:V2Colors.navy)),
            IconButton(tooltip:'Santé',onPressed:loading?null:()=>showPage('health'),icon:const Icon(Icons.health_and_safety_outlined,color:V2Colors.navy)),
            IconButton(tooltip:'Reproduction',onPressed:loading?null:()=>showPage('breeding'),icon:const Icon(Icons.autorenew,color:V2Colors.navy)),
          ]),
          () => showPage('management_hub'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Material(type:MaterialType.transparency,child:Column(
    children: [
      if (loading) const LinearProgressIndicator(),
      Expanded(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if(page=='dashboard')Center(child:Padding(padding:const EdgeInsets.symmetric(vertical:24),child:Text.rich(TextSpan(children:[const TextSpan(text:'Tableau de bord ',style:TextStyle(color:V2Colors.navy)),TextSpan(text:widget.farmName,style:const TextStyle(color:V2Colors.green))]),textAlign:TextAlign.center,style:const TextStyle(fontFamily:'Roboto',fontSize:42,fontWeight:FontWeight.bold)))),
                const SizedBox(height: 12),
                if(page!='dashboard')Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (page != 'dashboard')
                      TextButton.icon(
                        onPressed: goBack,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Retour'),
                      ),
                    TextButton.icon(
                      onPressed: showDashboard,
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Accueil'),
                    ),
                    if (aquaticMenuTitles.containsKey(page))
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          aquaticMenuTitles[page]!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                  ],
                ),
                if (aquaticMenuGroups.containsKey(page))
                  menuHub(aquaticMenuGroups[page]!),
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
                  if(financialSummary?['period'] is Map)
                    Padding(padding:const EdgeInsets.only(bottom:12),child:Text("Du ${financialSummary!['period']['from']} au ${financialSummary!['period']['to']}")),
                  if (dashboard != null) dashboardCards(),
                  if ((dashboard?['metrics']?['live_count']
                          as Map?)?['quality'] ==
                      'UNRECONCILED')
                    Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      const Text('Brut non rapproché'),
                      Text("Plage ${dashboard?['metrics']['live_count']['lower']} à ${dashboard?['metrics']['live_count']['upper']}"),
                    ]),
                  if ((dashboard?['unassigned_losses'] as num? ?? 0)>0 || (dashboard?['unassigned_credits'] as num? ?? 0)>0)
                    Text(
                      'Pertes à rapprocher : ${dashboard?['unassigned_losses']} · Crédits non affectés : ${dashboard?['unassigned_credits'] ?? 0}',
                    ),
                  const SizedBox(height:20),
                  AquaticDashboardAgenda(key:ValueKey('agenda:$speciesFilter:$installationFilter:$cohortFilter'),service:widget.service,filters:{'species':?speciesFilter,'installation':?installationFilter,'cohort':?cohortFilter},canPlan:allows('aquatic.agenda.plan'),openAgenda:()=>showPage('agenda'),addTask:(){showPage('agenda');setState(()=>planningAction='TASK');}),
                ],
                if(page=='stock_detail')...[
                  const Text('Stock piscicole',style:TextStyle(fontWeight:FontWeight.bold)),
                  if(dashboard?['metrics']?['live_count'] is Map)Text('${dashboard?['metrics']['live_count']['value']??'—'} poissons vivants'),
                  Text('${dashboard?['metrics']?['active_installations']?['value']??'—'} installations actives · ${dashboard?['metrics']?['active_cohorts']?['value']??'—'} cohortes actives'),
                  if(dashboard?['metrics']?['live_count']?['quality']=='UNRECONCILED')Text('Brut non rapproché · plage ${dashboard?['metrics']['live_count']['lower']} à ${dashboard?['metrics']['live_count']['upper']}'),
                  if(dashboard?['unassigned_losses']!=null)Text('Pertes à rapprocher : ${dashboard?['unassigned_losses']}'),
                  for(final group in ['by_species','by_installation'])for(final row in dashboard?[group] as List? ?? [])ListTile(title:Text('${row['cohort__species__nom']??row['installation__name']}'),trailing:Text('${row['count']} poissons${row['quality']=='UNRECONCILED'?' · brut non rapproché':''}')),
                  for(final c in cohorts.where((c)=>(cohortFilter==null || c['id']==cohortFilter) && (speciesFilter==null || '${c['species']}'==speciesFilter) && (installationFilter==null || (c['positions'] as List? ?? []).any((p)=>p['installation']==installationFilter))))ListTile(title:Text('${c['name']}'),onTap:()=>detail('cohort',c)),
                  Wrap(spacing:12,runSpacing:12,children:[TextButton(onPressed:()=>showPage('stock'),child:const Text('Mouvements et rapprochements')),TextButton(onPressed:()=>showPage('cohorts'),child:const Text('Cohortes')),TextButton(onPressed:()=>showPage('installations'),child:const Text('Installations'))]),
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
                    initialSection: planningSection,
                    initialSpecies: speciesFilter,
                    key: ValueKey(
                      '$page:$planningSection:$planningInstallation:$planningCohort:$planningAction',
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
                    initialSection: commerceSection,
                    initialSpecies: speciesFilter,
                    key: ValueKey(
                      '$commerceSection:$commerceInstallation:$commerceCohort:$commerceAction',
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
                if (page=='feeding' && dashboard?['feeding_overview'] is Map)ExpansionTile(title:const Text('Bilan des distributions'),children:[feedingOverview(dashboard!['feeding_overview'] as Map)]),
                if (page == 'feeding')
                  FeedingPanel(
                    key: ValueKey('feeding:$feedingAction'),
                    initialInstallation: installationFilter,
                    initialCohort: cohortFilter,
                    initialAction: feedingAction,
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
                    key: ValueKey('stock:$stockAction'),
                    initialInstallation: installationFilter,
                    initialCohort: cohortFilter,
                    initialAction: stockAction,
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
                    initialTarget: page == 'weights'
                        ? (cohortFilter ?? installationFilter)
                        : installationFilter,
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
  ));
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
