import 'package:flutter/material.dart';
import '../theme/design_system_v2.dart';
import '../widgets/v2_components.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import 'aquatic_service.dart';
import 'feeding_panel.dart' show feedCard, feedWhen, feedDate, feedDay;

const planKinds = {
  'WATER': 'Contrôle de l’eau',
  'WEIGHT': 'Pesée',
  'FEED': 'Distribution d’aliment',
  'OBSERVATION': 'Observation sanitaire',
  'TREATMENT': 'Traitement',
  'REPRODUCTION': 'Reproduction',
  'HATCH_CHECK': 'Contrôle d’incubation ou d’éclosion',
  'HARVEST': 'Récolte',
  'OTHER': 'Autre opération',
};
const costScopes = {
  'COHORT': 'Cohorte',
  'INSTALLATION': 'Installation',
  'AQUATIC': 'Commun à la pisciculture',
  'FARM': 'Commun à toute l’exploitation',
};
String planningError(Object e) {
  final s = '$e';
  if (s.contains('STALE') || s.contains('VERSION')) {
    return 'Les informations ont changé. Actualisez avant de corriger.';
  }
  if (s.contains('SUPPLY_EXPENSE')) {
    return 'Cet achat possède déjà sa dépense. Utilisez son parcours d’origine pour corriger le montant ; seule son attribution est modifiable ici.';
  }
  if (s.contains('TASK_ACT')) {
    return 'L’acte choisi ne correspond pas au type ou au périmètre de cette tâche.';
  }
  if (s.contains('REMINDER_AFTER')) {
    return 'Le rappel doit précéder l’heure planifiée.';
  }
  return 'Opération refusée. Vérifiez les droits, les références, les dates et les montants.';
}

String planningAt(DateTime d) {
  if (d.isUtc) return d.toIso8601String();
  final n = d.timeZoneOffset.inMinutes;
  return '${d.toIso8601String()}${n < 0 ? '-' : '+'}${(n.abs() ~/ 60).toString().padLeft(2, '0')}:${(n.abs() % 60).toString().padLeft(2, '0')}';
}

String planningMoney(dynamic n) =>
    '${n ?? 'Non renseigné'} ${AppSettings.instance.currencyCode}';

class FinanceAgendaPanel extends StatefulWidget {
  const FinanceAgendaPanel({
    super.key,
    required this.service,
    required this.agenda,
    required this.owner,
    required this.rights,
    required this.installations,
    required this.cohorts,
    required this.species,
    this.initialSpecies,
    this.initialInstallation,
    this.initialCohort,
    this.initialAction,
    this.initialSection='summary',
    this.onChanged,
  });
  final AquaticService service;
  final bool agenda, owner;
  final List<String> rights;
  final List<Map<String, dynamic>> installations, cohorts, species;
  final String? initialInstallation, initialCohort, initialAction, initialSpecies;
  final String initialSection;
  final Future<void> Function()? onChanged;
  @override
  State<FinanceAgendaPanel> createState() => _FinanceAgendaPanelState();
}

class _FinanceAgendaPanelState extends State<FinanceAgendaPanel> {
  int generation = 0;
  bool loading = true, opened = false, mine = true;
  String? error, cohort, site, species;
  String section = 'summary';
  DateTime start = DateTime.now(), end = DateTime.now();
  Map<String, dynamic>? summary;
  List<Map<String, dynamic>> expenses = [],
      revenues = [],
      categories = [],
      tasks = [],
      reminders = [];
  bool allows(String r) => widget.owner || widget.rights.contains(r);
  @override
  void initState() {
    super.initState();
    species = widget.initialSpecies;
    cohort = widget.initialCohort;
    site = widget.initialInstallation;
    start = widget.agenda
        ? DateTime.now().subtract(const Duration(days: 7))
        : DateTime(DateTime.now().year, DateTime.now().month, 1);
    end = widget.agenda
        ? DateTime.now().add(const Duration(days: 30))
        : DateTime.now();
    section = widget.agenda ? 'tasks' : widget.initialSection;
    load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> load() async {
    final epoch = ++generation, identity = ApiService.sessionIdentity;
    setState(() {
      loading = true;
      error = null;
    });
    final filters = <String, String>{
      'from': feedDay(start),
      'to': feedDay(end),
      'cohort': ?cohort,
      'installation': ?site,
      'species': ?species,
      if (widget.agenda) 'mine': '$mine',
    };
    final q = Uri(queryParameters: filters).query;
    try {
      Map<String, dynamic>? s;
      List<Map<String, dynamic>> es = [], rs = [], cs = [], ts = [], ms = [];
      if (widget.agenda) {
        ts = await widget.service.list('agenda/?$q');
        ms = await widget.service.list(
          'agenda/?${Uri(queryParameters: {...filters, 'reminders': 'true'}).query}',
        );
      } else {
        s = await widget.service.read('finance-summary/?$q');
        es = await widget.service.list('finance-expenses/?$q');
        rs = await widget.service.list('finance-revenues/?$q');
        cs = List<Map<String, dynamic>>.from(
          (await widget.service.read('finance-categories/'))['categories']
              as List,
        );
      }
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        summary = s;
        expenses = es;
        revenues = rs;
        categories = cs;
        tasks = ts;
        reminders = ms;
        loading = false;
      });
      if (widget.initialAction != null && !opened) {
        opened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) edit(widget.initialAction!);
        });
      }
    } catch (e) {
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        summary = null;
        expenses = [];
        revenues = [];
        categories = [];
        tasks = [];
        reminders = [];
        loading = false;
        error =
            'Lecture impossible. Les anciennes données ont été masquées. Actualisez.';
      });
    }
  }

  Future<void> edit(String mode, {Map<String, dynamic>? row}) async {
    final identity = ApiService.sessionIdentity;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => PlanningEditor(
        service: widget.service,
        mode: mode,
        owner: widget.owner,
        installations: widget.installations,
        cohorts: widget.cohorts,
        categories: categories,
        row: row,
        initialInstallation: site,
        initialCohort: cohort,
      ),
    );
    if (changed == true && mounted && identity == ApiService.sessionIdentity) {
      await widget.onChanged?.call();
      if (mounted && identity == ApiService.sessionIdentity) await load();
    }
  }

  String changes(dynamic value) {
    if (value is! Map || value.isEmpty) return 'Non renseigné';
    const labels = {
      'title': 'Titre',
      'date': 'Date',
      'status': 'Statut',
      'montant': 'Montant',
      'note': 'Note',
      'scope': 'Périmètre',
      'cohort_id': 'Cohorte',
      'installation_id': 'Installation',
      'categorie_id': 'Catégorie',
      'description': 'Description',
      'scheduled_at': 'Heure planifiée',
      'reminder_at': 'Rappel',
      'report': 'Compte rendu',
      'cancellation_reason': 'Motif d’annulation',
      'kind': 'Type',
    };
    String v(String key, dynamic raw) {
      if (raw == null || raw == '') return 'Non renseigné';
      if (key == 'scope') return costScopes[raw] ?? '$raw';
      if (key == 'kind') return planKinds[raw] ?? '$raw';
      if (key == 'status') {
        return const {
              'TODO': 'À faire',
              'DONE': 'Terminée',
              'CANCELLED': 'Annulée',
            }[raw] ??
            '$raw';
      }
      final rows = key == 'cohort_id'
          ? widget.cohorts
          : key == 'installation_id'
          ? widget.installations
          : key == 'categorie_id'
          ? categories
          : const <Map<String, dynamic>>[];
      if (rows.isNotEmpty) {
        return rows
                .where((r) => '${r['id']}' == '$raw')
                .map((r) => '${r['name']}')
                .firstOrNull ??
            'Référence conservée';
      }
      return '$raw';
    }

    return value.entries
        .where((e) => labels.containsKey(e.key))
        .map((e) => '${labels[e.key]} : ${v(e.key as String, e.value)}')
        .join('\n');
  }

  Future<void> history(Map<String, dynamic> row) async {
    final identity = ApiService.sessionIdentity;
    try {
      final data = await widget.service.list(
        '${widget.agenda ? 'agenda-history' : 'finance-history'}/?target=${row['id']}',
      );
      if (!mounted || identity != ApiService.sessionIdentity) return;
      await showDialog<void>(
        context: context,
        builder: (d) => V2AlertDialog(
          backgroundColor: V2Colors.background,
          title: const Text('Historique des modifications'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in data) ...[
                    Text(
                      '${r['date']} · Auteur ${r['actor_name'] ?? r['actor']}\nMotif : ${r['reason']}',
                    ),
                    Text(
                      'Avant : ${changes(r['before'])}\nAprès : ${changes(r['after'])}',
                    ),
                    const Divider(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted && identity == ApiService.sessionIdentity) {
        setState(() => error = planningError(e));
      }
    }
  }

  Widget filter(
    String label,
    String? value,
    List<Map<String, dynamic>> rows,
    ValueChanged<String?> change,
  ) => SizedBox(
    width: 240,
    child: DropdownButtonFormField<String>(
      initialValue: value ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('Tous')),
        for (final r in rows)
          DropdownMenuItem(
            value: '${r['id']}',
            child: Text('${r['name']}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        change(v == '' ? null : v);
        load();
      },
    ),
  );
  Widget cost(Map<String, dynamic> r) => feedCard([
    Text(
      '${r['category_name']} · ${planningMoney(r['amount'])}',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    Text(
      '${r['date']} · ${costScopes[r['scope']]}\n${r['cohort_name'] ?? r['installation_name'] ?? 'Sans répartition'}\n${r['note'] ?? ''}',
    ),
    if (r['source'] == 'SUPPLY_RECEIPT')
      const Text(
        'Dépense de l’achat déjà existante. Aucun nouvel achat ni stock créé ici.',
      ),
    Wrap(
      spacing: 8,
      children: [
        if (widget.owner)
          OutlinedButton(
            onPressed: () => edit('ASSIGN', row: r),
            child: const Text('Préciser l’attribution'),
          ),
        if (widget.owner && r['economic_editable'] == true && r['id'] != null)
          OutlinedButton(
            onPressed: () => edit('EXPENSE_EDIT', row: r),
            child: const Text('Corriger'),
          ),
        if (r['id'] != null)
          OutlinedButton(
            onPressed: () => history(r),
            child: const Text('Historique'),
          ),
      ],
    ),
  ]);
  Widget task(Map<String, dynamic> r) => feedCard([
    Text('${r['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
    Text(
      '${planKinds[r['kind']]} · ${r['date']}\nHeure : ${r['scheduled_at'] == null ? 'Non renseignée' : feedWhen({'occurred_at': r['scheduled_at']})}\n${r['status'] == 'DONE'
          ? 'Terminée (déclaré)'
          : r['status'] == 'CANCELLED'
          ? 'Annulée'
          : 'À faire'} · ${r['actor_name']}\n${r['description'] ?? ''}',
    ),
    if (r['reminder_at'] != null)
      Text(
        'Rappel visible dans l’application : ${feedWhen({'occurred_at': r['reminder_at']})}',
      ),
    if (r['actual_id'] != null)
      const Text(
        'Référence explicite à un acte déjà enregistré. Aucun acte créé par l’agenda.',
      ),
    Wrap(
      spacing: 8,
      children: [
        if (r['status'] == 'TODO' && allows('aquatic.agenda.plan'))
          OutlinedButton(
            onPressed: () => edit('TASK_EDIT', row: r),
            child: const Text('Modifier'),
          ),
        if (r['status'] == 'TODO' && allows('aquatic.agenda.progress'))
          OutlinedButton(
            onPressed: () => edit('STATUS', row: r),
            child: const Text('Déclarer terminée'),
          ),
        if (widget.owner && r['status'] != 'CANCELLED')
          OutlinedButton(
            onPressed: () => edit(
              'STATUS',
              row: {
                ...r,
                'desired_status': r['status'] == 'DONE' ? 'TODO' : 'CANCELLED',
              },
            ),
            child: Text(r['status'] == 'DONE' ? 'Rouvrir' : 'Annuler la tâche'),
          ),
        OutlinedButton(
          onPressed: () => history(r),
          child: const Text('Historique'),
        ),
      ],
    ),
  ]);
  @override
  Widget build(BuildContext context) => Theme(
    data: designSystemV2(Theme.of(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.agenda ? 'Agenda piscicole' : 'Finances piscicoles',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          widget.agenda
              ? 'Une tâche planifiée ou terminée ne crée aucun acte, mouvement de stock ou écriture financière.'
              : 'Factures, paiements et dépenses du système existant. Résultat indicatif, pas un bénéfice net comptable.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.agenda
              ? [
                  OutlinedButton(
                    onPressed: () => setState(() => section = 'tasks'),
                    child: const Text('Mes tâches'),
                  ),
                  if (allows('aquatic.agenda.plan'))
                    OutlinedButton.icon(
                      onPressed: loading ? null : () => edit('TASK'),
                      icon: const Icon(Icons.add_task, color: V2Colors.green),
                      label: const Text('Ajouter une tâche'),
                    ),
                  OutlinedButton(
                    onPressed: () => setState(() => section = 'done'),
                    child: const Text('Tâches terminées'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => section = 'reminders'),
                    child: const Text('Rappels'),
                  ),
                ]
              : [
                  for (final pair in const [
                    ['summary', 'Synthèse'],
                    ['expenses', 'Dépenses'],
                    ['revenues', 'Recettes et paiements'],
                    ['common', 'Coûts communs'],
                  ])
                    OutlinedButton(
                      onPressed: () => setState(() => section = pair[0]),
                      child: Text(pair[1]),
                    ),
                  if (allows('aquatic.finances.manage') &&
                      allows('expenses.create'))
                    OutlinedButton.icon(
                      onPressed: loading ? null : () => edit('EXPENSE'),
                      icon: const Icon(Icons.add, color: V2Colors.green),
                      label: const Text('Ajouter une dépense'),
                    ),
                ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            filter('Installation', site, widget.installations, (v) => site = v),
            filter('Cohorte', cohort, widget.cohorts, (v) => cohort = v),
            filter('Espèce', species, widget.species, (v) => species = v),
            OutlinedButton.icon(
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDateRange: DateTimeRange(start: start, end: end),
                );
                if (range != null) {
                  setState(() {
                    start = range.start;
                    end = range.end;
                  });
                  load();
                }
              },
              icon: const Icon(Icons.calendar_month, color: V2Colors.green),
              label: Text('${feedDate(start)} au ${feedDate(end)}'),
            ),
            OutlinedButton(onPressed: load, child: const Text('Actualiser')),
          ],
        ),
        if (widget.agenda && widget.owner)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mes tâches uniquement'),
            value: mine,
            onChanged: (v) {
              setState(() => mine = v ?? true);
              load();
            },
          ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        if (!loading &&
            !widget.agenda &&
            summary != null &&
            section == 'summary') ...[
          for (final pair in const [
            ['billed_revenue', 'Chiffre d’affaires facturé'],
            ['aquatic_expenses', 'Dépenses piscicoles retenues'],
            ['estimated_result', 'Résultat estimatif'],
            ['received_payments', 'Encaissements reçus sur la période'],
            ['client_balance_as_of', 'Solde clients à la date de fin'],
            [
              'aquatic_common_expenses',
              'Coûts communs piscicoles de la période',
            ],
            [
              'farm_common_expenses',
              'Coûts communs à l’exploitation (non soustraits)',
            ],
          ])
            feedCard([
              Text(pair[1]),
              Text(
                planningMoney(summary![pair[0]]),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ]),
          Text(
            summary!['origin_filtered'] == true
                ? 'Les coûts communs ne sont pas soustraits dans ce périmètre filtré.'
                : 'Le résultat inclut les coûts directs et communs à la pisciculture ; les coûts de l’exploitation non affectés restent exclus.',
          ),
          for (final line in summary!['limits'] as List? ?? []) Text('$line'),
          const SizedBox(height: 8),
          const Text('Dépenses retenues par catégorie'),
          for (final r in summary!['categories'] as List? ?? [])
            Text('${r['name']} : ${planningMoney(r['amount'])}'),
        ],
        if (!loading && !widget.agenda && section == 'expenses') ...[
          if (expenses.isEmpty) const Text('Aucune dépense dans ce périmètre.'),
          for (final r in expenses) cost(r),
        ],
        if (!loading && !widget.agenda && section == 'common') ...[
          const Text(
            'Coûts communs de la période, affichés séparément. Aucun montant n’est réparti entre cohortes.',
          ),
          for (final r in expenses.where(
            (r) => ['AQUATIC', 'FARM'].contains(r['scope']),
          ))
            cost(r),
        ],
        if (!loading && !widget.agenda && section == 'revenues') ...[
          const Text(
            'Factures de la période ou encaissées sur la période ; paiements et soldes à la date de fin. Une facture antérieure n’est pas ajoutée au chiffre d’affaires de la période.',
          ),
          for (final r in revenues)
            feedCard([
              Text('${r['invoice_reference']} · ${r['client_name']}'),
              if (r['invoice_in_period'] == false)
                const Text(
                  'Facture antérieure à la période : seul l’encaissement de la période est retenu.',
                ),
              Text(
                '${r['date']} · ${r['cohort_name']} · ${r['installation_name']}\nFacturé : ${planningMoney(r['amount'])}\nPayé à la date de fin : ${planningMoney(r['paid_as_of'])}\nSolde : ${planningMoney(r['balance_as_of'])}',
              ),
              for (final p in r['payments'] as List? ?? [])
                Text('Paiement ${p['date']} : ${planningMoney(p['amount'])}'),
            ]),
        ],
        if (!loading && widget.agenda) ...[
          if (section == 'reminders')
            const Text(
              'Rappels échus pour les tâches à faire, indépendants de la période sélectionnée. Aucun push ni fréquence automatique.',
            ),
          for (final r
              in (section == 'reminders'
                  ? reminders
                  : tasks
                        .where(
                          (r) => section == 'done'
                              ? r['status'] == 'DONE'
                              : r['status'] != 'DONE',
                        )
                        .toList()))
            task(r),
        ],
      ],
    ),
  );
}

class PlanningEditor extends StatefulWidget {
  const PlanningEditor({
    super.key,
    required this.service,
    required this.mode,
    required this.owner,
    required this.installations,
    required this.cohorts,
    required this.categories,
    this.row,
    this.initialInstallation,
    this.initialCohort,
  });
  final AquaticService service;
  final String mode;
  final bool owner;
  final List<Map<String, dynamic>> installations, cohorts, categories;
  final Map<String, dynamic>? row;
  final String? initialInstallation, initialCohort;
  @override
  State<PlanningEditor> createState() => _PlanningEditorState();
}

class _PlanningEditorState extends State<PlanningEditor> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  TextEditingController c(String k) =>
      controllers.putIfAbsent(k, () => TextEditingController());
  final identity = ApiService.sessionIdentity;
  bool busy = false,
      uncertain = false,
      newCategory = false,
      timeKnown = false,
      reminder = false;
  String? error, cohort, site, category, actual;
  String scope = 'AQUATIC', kind = 'OTHER', status = 'DONE', actualKind = '';
  DateTime day = DateTime.now();
  TimeOfDay? time;
  DateTime? reminderAt;
  Map<String, dynamic>? pending;
  List<Map<String, dynamic>> facts = [];
  bool get isTask => widget.mode == 'TASK' || widget.mode == 'TASK_EDIT';
  bool get isStatus => widget.mode == 'STATUS';
  bool get assign => widget.mode == 'ASSIGN';
  @override
  void initState() {
    super.initState();
    final r = widget.row;
    cohort = r?['cohort'] ?? widget.initialCohort;
    site = r?['installation'] ?? widget.initialInstallation;
    scope =
        r?['scope'] ??
        (cohort != null
            ? 'COHORT'
            : site != null
            ? 'INSTALLATION'
            : 'AQUATIC');
    if (r != null) {
      for (final k in ['title', 'description', 'amount', 'note', 'report']) {
        c(k).text = '${r[k] ?? ''}';
      }
      category = r['category']?.toString();
      kind = r['kind'] ?? 'OTHER';
      day = DateTime.tryParse('${r['date']}') ?? day;
      final at = DateTime.tryParse('${r['scheduled_at']}')?.toLocal();
      if (at != null) {
        timeKnown = true;
        time = TimeOfDay.fromDateTime(at);
      }
      reminderAt = DateTime.tryParse('${r['reminder_at']}')?.toLocal();
      reminder = reminderAt != null;
      status = r['desired_status'] ?? 'DONE';
    }
    if (isStatus) {
      actualKind = {'HATCH_CHECK': 'HATCH'}.containsKey(kind)
          ? 'HATCH'
          : kind == 'OTHER'
          ? ''
          : kind;
    }
  }

  @override
  void dispose() {
    for (final x in controllers.values) {
      x.dispose();
    }
    super.dispose();
  }

  Widget field(
    String k,
    String label, {
    bool optional = false,
    bool money = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: c(k),
      decoration: InputDecoration(labelText: label),
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      validator: (v) {
        final s = v?.trim().replaceAll(',', '.') ?? '';
        if (optional && s.isEmpty) return null;
        if (s.isEmpty) return 'Champ requis.';
        if (money &&
            (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s) ||
                (num.tryParse(s) ?? 0) <= 0)) {
          return 'Montant positif avec deux décimales maximum.';
        }
        return null;
      },
    ),
  );
  Widget select(
    String label,
    String? value,
    List<Map<String, dynamic>> rows,
    ValueChanged<String?> change, {
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      initialValue: rows.any((r) => '${r['id']}' == value)
          ? value
          : optional
          ? ''
          : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (optional)
          const DropdownMenuItem(value: '', child: Text('Non renseigné')),
        for (final r in rows)
          DropdownMenuItem(
            value: '${r['id']}',
            child: Text('${r['name']}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => change(v == '' ? null : v),
      validator: optional
          ? null
          : (v) => v == null ? 'Choisissez une référence.' : null,
    ),
  );
  Future<void> chooseDate({bool remind = false}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: remind ? (reminderAt ?? day) : day,
      firstDate: DateTime(2000),
      lastDate: isTask ? DateTime(2100) : DateTime.now(),
    );
    if (d == null || !mounted) return;
    if (remind) {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(reminderAt ?? DateTime.now()),
      );
      if (t != null) {
        setState(
          () => reminderAt = DateTime(d.year, d.month, d.day, t.hour, t.minute),
        );
      }
    } else {
      setState(() => day = d);
    }
  }

  Future<void> loadFacts() async {
    if (actualKind.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      facts = [];
      actual = null;
    });
    try {
      final paths = {
        'WATER': 'water-readings/',
        'WEIGHT': 'weights/',
        'FEED': 'feed-distributions/',
        'OBSERVATION': 'health-observations/',
        'TREATMENT': 'health-treatments/',
        'REPRODUCTION': 'reproductions/',
        'HATCH': 'breeding-facts/?kind=HATCH',
        'HARVEST': 'harvests/',
      };
      final result = await widget.service.list(paths[actualKind]!);
      if (!mounted || identity != ApiService.sessionIdentity) return;
      setState(
        () => facts = result
            .map(
              (r) => {
                ...r,
                'name':
                    '${feedWhen(r)} · ${r['installation_name'] ?? r['group_name'] ?? r['note'] ?? 'Acte enregistré'}',
              },
            )
            .toList(),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Impossible de charger les actes. Aucun acte n’a été créé.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Map<String, dynamic> body() {
    if (isStatus) {
      return {
        'target': widget.row!['id'],
        'expected_version': widget.row!['version'],
        'status': status,
        'reason': c('reason').text.trim(),
        'report': c('report').text.trim(),
        'actual_kind': actual == null ? '' : actualKind,
        'actual_id': actual,
      };
    }
    if (isTask) {
      return {
        if (widget.row != null) 'target': widget.row!['id'],
        if (widget.row != null) 'expected_version': widget.row!['version'],
        if (widget.row != null) 'reason': c('reason').text.trim(),
        'title': c('title').text.trim(),
        'kind': kind,
        'date': feedDay(day),
        'scheduled_at': timeKnown
            ? planningAt(
                DateTime(
                  day.year,
                  day.month,
                  day.day,
                  time!.hour,
                  time!.minute,
                ),
              )
            : null,
        'reminder_at': reminder ? planningAt(reminderAt!) : null,
        'cohort': cohort,
        'installation': site,
        'description': c('description').text.trim(),
      };
    }
    return {
      'scope': scope,
      'cohort': scope == 'COHORT' ? cohort : null,
      'installation': ['COHORT', 'INSTALLATION'].contains(scope) ? site : null,
      'reason': c('reason').text.trim(),
      if (assign) 'expense': widget.row!['expense_id'],
      if (assign) 'expected_version': widget.row!['version'],
      if (!assign) ...{
        if (widget.row != null) 'target': widget.row!['id'],
        if (widget.row != null) 'expected_version': widget.row!['version'],
        if (newCategory) 'new_category': c('new_category').text.trim(),
        if (!newCategory) 'category': int.parse(category!),
        'amount': c('amount').text.trim().replaceAll(',', '.'),
        'date': feedDay(day),
        'note': c('note').text.trim(),
      },
    };
  }

  String get path => isStatus
      ? 'agenda-status/'
      : isTask
      ? (widget.row == null ? 'agenda/' : 'agenda-revisions/')
      : assign
      ? 'finance-assignments/'
      : widget.row == null
      ? 'finance-expenses/'
      : 'finance-expense-revisions/';
  Future<void> save() async {
    if (identity != ApiService.sessionIdentity) {
      setState(
        () => error = 'Session modifiée. Fermez et ouvrez une nouvelle saisie.',
      );
      return;
    }
    if (!uncertain) {
      if (!form.currentState!.validate()) return;
      if (isTask &&
          ((timeKnown && time == null) || (reminder && reminderAt == null))) {
        setState(
          () =>
              error = 'Choisissez explicitement l’heure ou la date du rappel.',
        );
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      pending ??= widget.service.command(body());
      await widget.service.send(path, pending!);
      if (!mounted || identity != ApiService.sessionIdentity) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted || identity != ApiService.sessionIdentity) return;
      final known =
          e is ApiHttpException &&
          e.status >= 400 &&
          e.status < 500 &&
          e.status != 408;
      setState(() {
        busy = false;
        uncertain = !known;
        if (known) pending = null;
        error = known
            ? planningError(e)
            : 'Réponse non reçue. Réessayez la même opération pour éviter un doublon.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: designSystemV2(Theme.of(context)),
    child: V2AlertDialog(
      backgroundColor: V2Colors.background,
      title: Text(
        isStatus
            ? 'État de la tâche'
            : isTask
            ? (widget.row == null ? 'Ajouter une tâche' : 'Modifier la tâche')
            : assign
            ? 'Préciser l’attribution'
            : widget.row == null
            ? 'Ajouter une dépense'
            : 'Corriger la dépense',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: AbsorbPointer(
            absorbing: busy || uncertain,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isStatus) ...[
                    Text(
                      '${widget.row!['title']}\nUne déclaration de statut ne crée aucun acte métier.',
                    ),
                    select(
                      'Statut',
                      status,
                      [
                        if (widget.owner) {'id': 'TODO', 'name': 'À faire'},
                        {'id': 'DONE', 'name': 'Terminée (déclaré)'},
                        if (widget.owner)
                          {'id': 'CANCELLED', 'name': 'Annulée'},
                      ],
                      (v) => setState(() {
                        status = v!;
                        actual = null;
                      }),
                    ),
                    field('reason', 'Motif'),
                    field(
                      'report',
                      'Compte rendu (facultatif)',
                      optional: true,
                    ),
                    if (status == 'DONE')
                      ExpansionTile(
                        maintainState: true,
                        title: const Text(
                          'Relier un acte déjà enregistré (facultatif)',
                        ),
                        children: [
                          if (kind == 'OTHER')
                            select(
                              'Type d’acte',
                              actualKind,
                              planKinds.entries
                                  .where((e) => e.key != 'OTHER')
                                  .map(
                                    (e) => {
                                      'id': e.key == 'HATCH_CHECK'
                                          ? 'HATCH'
                                          : e.key,
                                      'name': e.value,
                                    },
                                  )
                                  .toList(),
                              (v) => setState(() {
                                actualKind = v ?? '';
                                facts = [];
                                actual = null;
                              }),
                              optional: true,
                            ),
                          OutlinedButton(
                            onPressed: loadFacts,
                            child: const Text('Charger les actes existants'),
                          ),
                          select(
                            'Acte réalisé',
                            actual,
                            facts,
                            (v) => setState(() => actual = v),
                            optional: true,
                          ),
                        ],
                      ),
                  ],
                  if (isTask) ...[
                    const Text(
                      'Planification uniquement. Pas de débit de stock, de traitement administré ni de dépense automatiques.',
                    ),
                    field('title', 'Titre'),
                    select(
                      'Type d’opération',
                      kind,
                      planKinds.entries
                          .map((e) => {'id': e.key, 'name': e.value})
                          .toList(),
                      (v) => setState(() => kind = v!),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => chooseDate(),
                      icon: const Icon(
                        Icons.calendar_month,
                        color: V2Colors.green,
                      ),
                      label: Text('Date : ${feedDate(day)}'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: timeKnown,
                      onChanged: (v) => setState(() => timeKnown = v ?? false),
                      title: const Text('Heure connue (facultatif)'),
                    ),
                    if (timeKnown)
                      OutlinedButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: time ?? TimeOfDay.now(),
                          );
                          if (t != null) setState(() => time = t);
                        },
                        child: Text(
                          time == null
                              ? 'Choisir l’heure'
                              : 'Heure : ${time!.format(context)}',
                        ),
                      ),
                    select(
                      'Installation (facultative)',
                      site,
                      widget.installations,
                      (v) => setState(() => site = v),
                      optional: true,
                    ),
                    select(
                      'Cohorte (facultative)',
                      cohort,
                      widget.cohorts,
                      (v) => setState(() => cohort = v),
                      optional: true,
                    ),
                    field(
                      'description',
                      'Description (facultative)',
                      optional: true,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: reminder,
                      onChanged: (v) => setState(() => reminder = v ?? false),
                      title: const Text('Rappel visible dans l’application'),
                    ),
                    if (reminder)
                      OutlinedButton(
                        onPressed: () => chooseDate(remind: true),
                        child: Text(
                          reminderAt == null
                              ? 'Choisir le rappel'
                              : feedWhen({
                                  'occurred_at': reminderAt!.toIso8601String(),
                                }),
                        ),
                      ),
                    if (widget.row != null)
                      field('reason', 'Motif de modification'),
                  ],
                  if (!isTask && !isStatus) ...[
                    const Text(
                      'Une seule dépense économique. Les achats alimentaires ont déjà leur dépense : précisez leur attribution sans les recréer.',
                    ),
                    select(
                      'Périmètre',
                      scope,
                      costScopes.entries
                          .map((e) => {'id': e.key, 'name': e.value})
                          .toList(),
                      (v) => setState(() => scope = v!),
                    ),
                    if (scope == 'COHORT')
                      select(
                        'Cohorte',
                        cohort,
                        widget.cohorts,
                        (v) => setState(() => cohort = v),
                      ),
                    if (scope == 'INSTALLATION' || scope == 'COHORT')
                      select(
                        scope == 'COHORT'
                            ? 'Installation (facultative)'
                            : 'Installation',
                        site,
                        widget.installations,
                        (v) => setState(() => site = v),
                        optional: scope == 'COHORT',
                      ),
                    if (!assign) ...[
                      if (widget.owner)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: newCategory,
                          onChanged: (v) =>
                              setState(() => newCategory = v ?? false),
                          title: const Text('Nouvelle catégorie libre'),
                        ),
                      if (newCategory)
                        field('new_category', 'Nom de la catégorie')
                      else
                        select(
                          'Catégorie',
                          category,
                          widget.categories,
                          (v) => setState(() => category = v),
                        ),
                      field(
                        'amount',
                        'Montant (${AppSettings.instance.currencyCode})',
                        money: true,
                      ),
                      OutlinedButton.icon(
                        onPressed: () => chooseDate(),
                        icon: const Icon(
                          Icons.calendar_month,
                          color: V2Colors.green,
                        ),
                        label: Text('Date : ${feedDate(day)}'),
                      ),
                      field('note', 'Note (facultative)', optional: true),
                    ],
                    field('reason', 'Motif'),
                  ],
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(uncertain ? 'Fermer (résultat à vérifier)' : 'Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: V2Colors.navy,
            foregroundColor: Colors.white,
          ),
          onPressed: busy ? null : save,
          child: Text(
            uncertain ? 'Réessayer la même opération' : 'Enregistrer',
          ),
        ),
      ],
    ),
  );
}
