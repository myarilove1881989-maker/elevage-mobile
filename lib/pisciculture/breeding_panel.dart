import 'package:flutter/material.dart';
import '../theme/design_system_v2.dart';
import '../widgets/v2_components.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';
import 'feeding_panel.dart' show feedCard, feedDate, feedDay, feedWhen;

String breedingKind(dynamic value) =>
    const {
      'SPAWN': 'Ponte',
      'INCUBATION': 'Incubation',
      'HATCH': 'Éclosion',
      'COUNT': 'Comptage confirmé',
      'PLACEMENT': 'Mise en élevage',
      'VOID': 'Annulation compensatoire',
    }[value] ??
    '$value';
String breedingQuality(dynamic value) =>
    const {
      'UNKNOWN': 'Inconnu',
      'ESTIMATED': 'Estimé',
      'COUNTED': 'Compté',
    }[value] ??
    '$value';
String breedingError(Object e) {
  final text = '$e';
  if (text.contains('HATCH_COUNT_CONFIRMATION_REQUIRED')) {
    return 'Confirmez un comptage réel du lot d’éclosion avant la mise en élevage.';
  }
  if (text.contains('HATCH_CONFIRMED_QUANTITY_EXCEEDED')) {
    return 'L’effectif confirmé disponible est insuffisant. Actualisez ou renseignez un nouveau comptage réel.';
  }
  if (text.contains('FRY_COHORT_HAS_DEPENDENTS') ||
      text.contains('DEPENDENTS_MUST_BE_VOIDED')) {
    return 'Des opérations dépendent déjà de ce constat. L’annulation est refusée pour préserver l’historique et les effectifs.';
  }
  if (text.contains('STALE') || text.contains('CLOSED')) {
    return 'Les informations ont changé ou la reproduction est clôturée. Actualisez avant de recommencer.';
  }
  if (text.contains('TIMELINE') ||
      text.contains('BEFORE') ||
      text.contains('AT_DATE')) {
    return 'Vérifiez la chronologie et la présence des poissons à la date choisie.';
  }
  return 'Opération refusée. Vérifiez les droits, les dates, les références et les quantités.';
}

class BreedingPanel extends StatefulWidget {
  const BreedingPanel({
    super.key,
    required this.service,
    required this.owner,
    required this.rights,
    required this.installations,
    required this.cohorts,
    required this.species,
    this.initialInstallation,
    this.initialCohort,
    this.initialAction,
    this.onChanged,
  });
  final AquaticService service;
  final bool owner;
  final List<String> rights;
  final List<Map<String, dynamic>> installations, cohorts, species;
  final String? initialInstallation, initialCohort, initialAction;
  final Future<void> Function()? onChanged;
  @override
  State<BreedingPanel> createState() => _BreedingPanelState();
}

class _BreedingPanelState extends State<BreedingPanel> {
  List<Map<String, dynamic>> groups = [],
      reproductions = [],
      facts = [],
      history = [],
      stages = [];
  String section = 'reproductions';
  String? site, group, species, status, error;
  DateTime start = DateTime.now().subtract(const Duration(days: 29)),
      end = DateTime.now();
  bool busy = true, opened = false;
  int generation = 0;
  bool allows(String code) => widget.owner || widget.rights.contains(code);
  @override
  void initState() {
    super.initState();
    site = widget.initialInstallation;
    load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  String query() =>
      '?${Uri(queryParameters: <String, String>{'installation': ?site, 'group': ?group, 'species': ?species, if (status == 'OPEN' || status == 'CLOSED') 'status': status!, 'from': DateTime(start.year, start.month, start.day).toUtc().toIso8601String(), 'to': DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toUtc().toIso8601String()}).query}';
  Future<void> load() async {
    final epoch = ++generation, identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
      groups = [];
      reproductions = [];
      facts = [];
      history = [];
      stages = [];
    });
    try {
      final values = await Future.wait([
        widget.service.list('brood-groups/'),
        widget.service.list('reproductions/'),
        widget.service.list('breeding-facts/'),
        widget.service.list('breeding-facts/${query()}'),
        widget.service.list('stages/'),
      ]);
      if (!mounted ||
          generation != epoch ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        groups = values[0];
        reproductions = values[1];
        facts = values[2];
        history = values[3];
        stages = values[4];
        busy = false;
      });
      if (!opened && widget.initialAction != null) {
        opened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) edit(widget.initialAction!);
        });
      }
    } catch (_) {
      if (!mounted ||
          generation != epoch ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        busy = false;
        error =
            'Reproduction indisponible. Vérifiez la connexion et vos droits, puis actualisez.';
      });
    }
  }

  Future<bool> edit(
    String kind, {
    Map<String, dynamic>? initial,
    String? reproduction,
  }) async {
    final identity = ApiService.sessionIdentity;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BreedingEditor(
        service: widget.service,
        kind: kind,
        groups: groups,
        reproductions: reproductions,
        facts: facts,
        stages: stages,
        installations: widget.installations,
        cohorts: widget.cohorts,
        species: widget.species,
        initial: initial,
        initialInstallation: site,
        initialCohort: widget.initialCohort,
        initialReproduction: reproduction,
      ),
    );
    if (changed == true && mounted && identity == ApiService.sessionIdentity) {
      await load();
      if (mounted && identity == ApiService.sessionIdentity) {
        await widget.onChanged?.call();
      }
      return true;
    }
    return false;
  }

  Future<void> detail(Map<String, dynamic> rep) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BreedingDetail(
        service: widget.service,
        reproduction: rep['id'] as String,
        canEdit: allows('aquatic.reproduction.create'),
        canStock:
            allows('aquatic.fry.stock') && allows('aquatic.cohorts.manage'),
        canCount: allows('aquatic.fry.stock'),
        owner: widget.owner,
        onEdit: (kind, row) =>
            edit(kind, initial: row, reproduction: rep['id'] as String),
      ),
    );
  }

  Future<void> groupHistory(Map<String, dynamic> group) async {
    final identity = ApiService.sessionIdentity;
    try {
      final rows = await widget.service.list(
        'breeding-revisions/?group=${group['id']}',
      );
      if (!mounted || identity != ApiService.sessionIdentity) return;
      await showDialog<void>(
        context: context,
        builder: (c) => V2AlertDialog(
          title: Text('Historique de ${group['name']}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rows.isEmpty)
                    const Text('Aucune modification enregistrée.'),
                  for (final row in rows)
                    feedCard([
                      Text('${feedWhen(row)} · auteur ${row['actor']}'),
                      Text('Motif : ${row['reason']}'),
                      for (final key in [
                        'name',
                        'status',
                        'males',
                        'females',
                        'note',
                      ])
                        if (row['before']?[key] != row['after']?[key])
                          Text(
                            '${const {'name': 'Nom', 'status': 'Statut', 'males': 'Mâles', 'females': 'Femelles', 'note': 'Note'}[key]} : ${row['before']?[key] ?? 'inconnu'} puis ${row['after']?[key] ?? 'inconnu'}',
                          ),
                    ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted && identity == ApiService.sessionIdentity) {
        setState(
          () =>
              error = 'Historique des modifications indisponible. Actualisez.',
        );
      }
    }
  }

  Widget filter(
    String label,
    String? value,
    List<Map<String, dynamic>> rows,
    ValueChanged<String?> change,
  ) => SizedBox(
    width: 260,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      isExpanded: true,
      initialValue: value,
      decoration: V2InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: null, child: Text('Tous')),
        ...rows.map(
          (r) => DropdownMenuItem(
            value: '${r['id']}',
            child: Text('${r['name']}', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: busy
          ? null
          : (v) {
              change(v);
              load();
            },
    ),
  );
  bool matches(Map r) =>
      (site == null || r['installation'] == site) &&
      (species == null || '${r['species']}' == species) &&
      (group == null || r['group'] == group || r['id'] == group) &&
      (status == null || r['status'] == status);
  Future<void> period() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (range != null && mounted) {
      setState(() {
        start = range.start;
        end = range.end;
      });
      load();
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: designSystemV2(Theme.of(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reproduction',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: V2Colors.navy,
          ),
        ),
        const Text(
          'Groupes, œufs et éclosions n’ajoutent aucun poisson au stock vivant. Seule la mise en élevage crée l’entrée dans une cohorte.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                section = 'groups';
                status = null;
              }),
              icon: const Icon(Icons.groups, color: V2Colors.green),
              label: const Text('Mes géniteurs'),
            ),
            if (allows('aquatic.reproduction.create'))
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: V2Colors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy ? null : () => edit('REPRODUCTION'),
                icon: const Icon(Icons.water, color: V2Colors.green),
                label: const Text('Nouvelle reproduction'),
              ),
            if (allows('aquatic.reproduction.create'))
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: V2Colors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy ? null : () => edit('HATCH'),
                icon: const Icon(Icons.egg_alt, color: V2Colors.green),
                label: const Text('Enregistrer une éclosion'),
              ),
            if (allows('aquatic.fry.stock'))
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: V2Colors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy || !allows('aquatic.cohorts.manage')
                    ? null
                    : () => edit('PLACEMENT'),
                icon: const Icon(Icons.set_meal, color: V2Colors.green),
                label: const Text('Mettre les alevins en élevage'),
              ),
          ],
        ),
        if (allows('aquatic.fry.stock') && !allows('aquatic.cohorts.manage'))
          const Text(
            'La mise en élevage nécessite aussi l’autorisation de créer une cohorte.',
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            filter('Installation', site, widget.installations, (v) => site = v),
            filter('Espèce', species, widget.species, (v) => species = v),
            filter('Groupe', group, groups, (v) => group = v),
            filter('Statut', status, [
              for (final v
                  in section == 'groups'
                      ? ['ACTIVE', 'INACTIVE']
                      : ['OPEN', 'CLOSED'])
                {
                  'id': v,
                  'name': const {
                    'ACTIVE': 'Actif',
                    'INACTIVE': 'Inactif',
                    'OPEN': 'Ouverte',
                    'CLOSED': 'Clôturée',
                  }[v],
                },
            ], (v) => status = v),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const {
              'reproductions': 'Reproductions',
              'groups': 'Géniteurs',
              'history': 'Historique',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: section == entry.key,
                selectedColor: V2Colors.navy,
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: section == entry.key ? Colors.white : V2Colors.navy,
                ),
                onSelected: (_) => setState(() {
                  section = entry.key;
                  status = null;
                }),
              ),
            OutlinedButton(
              onPressed: busy ? null : load,
              child: const Text('Actualiser'),
            ),
          ],
        ),
        if (section == 'groups') ...[
          if (allows('aquatic.breeders.manage'))
            OutlinedButton.icon(
              onPressed: busy ? null : () => edit('GROUP'),
              icon: const Icon(Icons.add, color: V2Colors.green),
              label: const Text('Créer un groupe de géniteurs'),
            ),
          const Text(
            'Ces groupes sont des repères descriptifs. Leurs effectifs ne s’ajoutent pas à ceux des cohortes et ne sont pas des réserves de poissons.',
          ),
          if (!busy && error == null && groups.where(matches).isEmpty)
            const Text('Aucun groupe pour ces filtres.'),
          for (final row in groups.where(matches))
            feedCard([
              Text(
                '${row['name']} · ${row['species_name']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${row['installation_name']} · ${row['status'] == 'ACTIVE' ? 'Actif' : 'Inactif'} · ${feedWhen(row)}',
              ),
              Text(
                'Mâles : ${row['males'] ?? 'inconnu'} · femelles : ${row['females'] ?? 'inconnu'}',
              ),
              Text(
                row['cohort'] == null
                    ? 'Cohorte d’origine non renseignée'
                    : 'Cohorte d’origine conservée, sans nouveau comptage',
              ),
              if ('${row['note'] ?? ''}'.isNotEmpty) Text('${row['note']}'),
              TextButton(
                onPressed: () => groupHistory(row),
                child: const Text('Historique du groupe'),
              ),
              if (widget.owner)
                TextButton(
                  onPressed: () => edit('GROUP_EDIT', initial: row),
                  child: const Text('Actualiser avec motif'),
                ),
            ]),
        ] else if (section == 'reproductions') ...[
          if (!busy && error == null && reproductions.where(matches).isEmpty)
            const Text('Aucune reproduction pour ces filtres.'),
          for (final row in reproductions.where(matches))
            feedCard([
              Text(
                '${row['group_name']} · ${row['species_name']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${feedWhen(row)} · ${row['installation_name']} · ${row['status'] == 'OPEN' ? 'Ouverte' : 'Clôturée'}',
              ),
              if ('${row['technique'] ?? ''}'.isNotEmpty)
                Text('Technique déclarée : ${row['technique']}'),
              TextButton(
                onPressed: () => detail(row),
                child: const Text('Voir les étapes et les alevins'),
              ),
              if (widget.owner)
                TextButton(
                  onPressed: () => edit('REP_STATUS', initial: row),
                  child: const Text('Modifier le statut avec motif'),
                ),
            ]),
        ] else ...[
          OutlinedButton.icon(
            onPressed: busy ? null : period,
            icon: const Icon(Icons.date_range, color: V2Colors.green),
            label: Text(
              'Période : ${feedDate(start.toIso8601String())} au ${feedDate(end.toIso8601String())}',
            ),
          ),
          if (!busy && error == null && history.isEmpty)
            const Text('Aucun événement pour ces filtres.'),
          for (final row in history.reversed)
            breedingFactCard(
              row,
              owner: widget.owner,
              onVoid: () => edit('VOID', initial: row),
            ),
        ],
        const Text(
          'Quantités inconnues distinctes de zéro. Aucun taux biologique, dépense ou acte hors ligne automatique.',
        ),
      ],
    ),
  );
}

Widget breedingFactCard(
  Map<String, dynamic> row, {
  bool owner = false,
  VoidCallback? onVoid,
}) => feedCard([
  Text(
    '${breedingKind(row['kind'])}${row['canceled'] == true ? ' · annulé, original conservé' : ''}',
    style: const TextStyle(fontWeight: FontWeight.bold, color: V2Colors.navy),
  ),
  Text(
    '${feedWhen(row)} · ${row['installation_name'] ?? ''} · ${row['group_name'] ?? ''}',
  ),
  if (!['VOID'].contains(row['kind']))
    Text(
      'Quantité : ${row['quantity'] ?? 'inconnue'} · ${breedingQuality(row['quality'])}',
    ),
  if (row['kind'] == 'HATCH') ...[
    const Text('Alevins observés ; pas encore une entrée de poissons vivants.'),
    Text(
      'Total confirmé : ${row['availability']?['confirmed_total'] ?? 'non renseigné'} · mis en élevage : ${row['availability']?['placed_total'] ?? 0} · disponible confirmé : ${row['availability']?['available_confirmed'] ?? 'inconnu'}',
    ),
  ],
  if (row['kind'] == 'PLACEMENT')
    const Text(
      'Entrée initiale tracée dans la cohorte. Les transferts et mortalités ultérieurs ne rendent pas cette quantité réutilisable à l’éclosion.',
    ),
  if ('${row['reason'] ?? ''}'.isNotEmpty) Text('Motif : ${row['reason']}'),
  if ('${row['note'] ?? ''}'.isNotEmpty) Text('Note : ${row['note']}'),
  Text(
    'Auteur : ${row['actor_name'] ?? row['actor']} · enregistré le ${feedDate(row['recorded_at'])}',
  ),
  if (owner && row['kind'] != 'VOID' && row['canceled'] != true)
    TextButton(onPressed: onVoid, child: const Text('Annuler avec motif')),
]);

class BreedingDetail extends StatefulWidget {
  const BreedingDetail({
    super.key,
    required this.service,
    required this.reproduction,
    required this.canEdit,
    required this.canStock,
    required this.canCount,
    required this.owner,
    required this.onEdit,
  });
  final AquaticService service;
  final String reproduction;
  final bool canEdit, canStock, canCount, owner;
  final Future<bool> Function(String, Map<String, dynamic>?) onEdit;
  @override
  State<BreedingDetail> createState() => _BreedingDetailState();
}

class _BreedingDetailState extends State<BreedingDetail> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
      data = null;
    });
    try {
      final d = await widget.service.read(
        'reproductions/${widget.reproduction}/',
      );
      if (!mounted || identity != ApiService.sessionIdentity) return;
      setState(() {
        data = d;
        busy = false;
      });
    } catch (_) {
      if (mounted && identity == ApiService.sessionIdentity) {
        setState(() {
          busy = false;
          error = 'Détail indisponible. Actualisez.';
        });
      }
    }
  }

  Future<void> edit(String kind, [Map<String, dynamic>? row]) async {
    if (await widget.onEdit(kind, row) && mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: designSystemV2(Theme.of(context)),
    child: V2AlertDialog(
      backgroundColor: V2Colors.background,
      title: const Text('Étapes de reproduction'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              if (data != null) ...[
                Text(
                  '${data!['group_name']} · ${data!['species_name']} · ${feedWhen(data!)}',
                ),
                const Text(
                  'Ponte et incubation sont facultatives. Les œufs et éclosions ne deviennent pas automatiquement des poissons suivis.',
                ),
                if (widget.canEdit && data!['status'] == 'OPEN')
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => edit('SPAWN'),
                        child: const Text('Enregistrer une ponte'),
                      ),
                      OutlinedButton(
                        onPressed: () => edit('INCUBATION'),
                        child: const Text('Enregistrer une incubation'),
                      ),
                      OutlinedButton(
                        onPressed: () => edit('HATCH'),
                        child: const Text('Enregistrer une éclosion'),
                      ),
                    ],
                  ),
                if ((data!['facts'] as List).isEmpty)
                  const Text('Aucune étape enregistrée.'),
                for (final raw in data!['facts'] as List) ...[
                  breedingFactCard(
                    Map<String, dynamic>.from(raw as Map),
                    owner: widget.owner,
                    onVoid: () => edit('VOID', Map<String, dynamic>.from(raw)),
                  ),
                  if (raw['kind'] == 'HATCH' &&
                      raw['canceled'] != true &&
                      data!['status'] == 'OPEN')
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (widget.canCount)
                          OutlinedButton(
                            onPressed: () =>
                                edit('COUNT', Map<String, dynamic>.from(raw)),
                            child: const Text('Confirmer un comptage'),
                          ),
                        if (widget.canStock)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: V2Colors.navy,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => edit(
                              'PLACEMENT',
                              Map<String, dynamic>.from(raw),
                            ),
                            child: const Text('Mettre ces alevins en élevage'),
                          ),
                      ],
                    ),
                ],
                const Text(
                  'Taux de fécondation et d’éclosion non calculés dans cette phase.',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : load,
          child: const Text('Actualiser'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

class BreedingEditor extends StatefulWidget {
  const BreedingEditor({
    super.key,
    required this.service,
    required this.kind,
    required this.groups,
    required this.reproductions,
    required this.facts,
    required this.stages,
    required this.installations,
    required this.cohorts,
    required this.species,
    this.initial,
    this.initialInstallation,
    this.initialCohort,
    this.initialReproduction,
  });
  final AquaticService service;
  final String kind;
  final List<Map<String, dynamic>> groups,
      reproductions,
      facts,
      stages,
      installations,
      cohorts,
      species;
  final Map<String, dynamic>? initial;
  final String? initialInstallation, initialCohort, initialReproduction;
  @override
  State<BreedingEditor> createState() => _BreedingEditorState();
}

class _BreedingEditorState extends State<BreedingEditor> {
  final form = GlobalKey<FormState>();
  final originIdentity = ApiService.sessionIdentity;
  final fields = <String, TextEditingController>{};
  TextEditingController c(String key) =>
      fields.putIfAbsent(key, () => TextEditingController());
  late String entityId;
  String? site,
      species,
      cohort,
      group,
      reproduction,
      hatch,
      parent,
      stage,
      status,
      error;
  String quality = 'UNKNOWN';
  DateTime at = DateTime.now();
  bool timeKnown = true,
      busy = false,
      uncertain = false,
      actuallyCounted = false,
      recount = false;
  Map<String, dynamic>? pending;
  bool get locked => busy || uncertain;
  bool get isGroup => widget.kind == 'GROUP';
  bool get groupEdit => widget.kind == 'GROUP_EDIT';
  bool get repEdit => widget.kind == 'REP_STATUS';
  bool get isRep => widget.kind == 'REPRODUCTION';
  bool get placement => widget.kind == 'PLACEMENT';
  bool get count => widget.kind == 'COUNT';
  bool get cancel => widget.kind == 'VOID';
  bool get step => ['SPAWN', 'INCUBATION', 'HATCH'].contains(widget.kind);
  Map<String, dynamic>? get chosenGroup =>
      widget.groups.where((r) => r['id'] == group).firstOrNull;
  Map<String, dynamic>? get chosenRep =>
      widget.reproductions.where((r) => r['id'] == reproduction).firstOrNull;
  Map<String, dynamic>? get chosenHatch =>
      widget.facts.where((r) => r['id'] == hatch).firstOrNull;
  bool get needsConfirmation =>
      placement &&
      chosenHatch != null &&
      (chosenHatch!['availability'] as Map?)?['confirmed_total'] == null;
  @override
  void initState() {
    super.initState();
    entityId = '${widget.service.command({})['operation_uuid']}';
    site = widget.initialInstallation;
    cohort = widget.initialCohort;
    reproduction = widget.initialReproduction;
    if (cohort != null) {
      final row = widget.cohorts.where((r) => r['id'] == cohort).firstOrNull;
      species = row?['species']?.toString();
      final positions = row?['positions'] as List? ?? [];
      if (site == null && positions.length == 1) {
        site = '${positions.first['installation']}';
      }
    }
    if (widget.initial != null) {
      final row = widget.initial!;
      if (placement || count) {
        hatch = '${row['id']}';
        reproduction = '${row['reproduction']}';
        site ??= '${row['installation']}';
      }
      if (groupEdit) {
        site = '${row['installation']}';
        species = '${row['species']}';
        cohort = row['cohort'] as String?;
        status = '${row['status']}';
        for (final key in ['name', 'note', 'males', 'females']) {
          c(key).text = '${row[key] ?? ''}';
        }
      }
      if (repEdit) status = '${row['status']}';
    }
    if (step && chosenRep != null) {
      site ??= chosenRep!['installation'] as String?;
    }
    if (placement) {
      c('name').text = 'Alevins du ${feedDate(at.toIso8601String())}';
      c('code').text = 'ALV-${entityId.substring(0, 12)}';
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget text(
    String key,
    String label, {
    bool optional = false,
    bool integer = false,
    bool zero = false,
    int max = 2000,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: c(key),
      enabled: !locked,
      maxLength: integer ? null : max,
      minLines: 1,
      maxLines: integer ? 1 : 3,
      keyboardType: integer ? TextInputType.number : TextInputType.multiline,
      decoration: V2InputDecoration(labelText: label),
      validator: (value) {
        final v = (value ?? '').trim();
        if (v.isEmpty) return optional ? null : 'Champ requis';
        if (integer) {
          final n = int.tryParse(v);
          if (!RegExp(r'^[0-9]+$').hasMatch(v) ||
              n == null ||
              n > 2147483647 ||
              n < (zero ? 0 : 1)) {
            return zero
                ? 'Entier entre 0 et 2 147 483 647 requis'
                : 'Entier strictement positif requis';
          }
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
    String empty = 'Non renseigné',
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      isExpanded: true,
      initialValue: rows.any((r) => '${r['id']}' == value) ? value : null,
      decoration: V2InputDecoration(labelText: label),
      items: [
        if (optional) DropdownMenuItem(value: null, child: Text(empty)),
        ...rows.map(
          (r) => DropdownMenuItem(
            value: '${r['id']}',
            child: Text('${r['name']}', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: locked ? null : (v) => setState(() => change(v)),
      validator: (v) => !optional && v == null ? 'Sélection requise' : null,
    ),
  );
  Future<void> date() async {
    final d = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null && mounted) {
      setState(() => at = DateTime(d.year, d.month, d.day, at.hour, at.minute));
    }
  }

  Future<void> hour() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
    );
    if (t != null && mounted) {
      setState(
        () => at = DateTime(at.year, at.month, at.day, t.hour, t.minute),
      );
    }
  }

  Map<String, dynamic> moment() {
    if (timeKnown || cancel) {
      return {
        'occurred_at': at.toUtc().toIso8601String(),
        if (!cancel) 'time_precision': 'DATETIME',
      };
    }
    final d = DateTime(at.year, at.month, at.day),
        offset = d.timeZoneOffset,
        m = offset.inMinutes.abs();
    return {
      'occurred_at':
          '${feedDay(d)}T00:00:00${offset.isNegative ? '-' : '+'}${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
      'time_precision': 'DATE',
      'business_date': feedDay(d),
    };
  }

  int? number(String key) =>
      c(key).text.trim().isEmpty ? null : int.parse(c(key).text.trim());
  Map<String, dynamic> body() {
    if (cancel) {
      return {
        'target': widget.initial!['id'],
        ...moment(),
        'reason': c('reason').text.trim(),
      };
    }
    if (repEdit) {
      return {
        'target': widget.initial!['id'],
        'expected_version': widget.initial!['version'],
        'status': status,
        'reason': c('reason').text.trim(),
      };
    }
    if (groupEdit) {
      final row = widget.initial!;
      return {
        'target': row['id'],
        'expected_version': row['version'],
        'reason': c('reason').text.trim(),
        if (site != row['installation']) 'installation': site,
        if (status != row['status']) 'status': status,
        for (final key in ['name', 'note'])
          if (c(key).text.trim() != '${row[key] ?? ''}')
            key: c(key).text.trim(),
        for (final key in ['males', 'females'])
          if (number(key) != row[key]) key: number(key),
      };
    }
    return {
      ...moment(),
      'installation': site,
      'note': c('note').text.trim(),
      if (isGroup) ...{
        'id': entityId,
        'name': c('name').text.trim(),
        'species': int.parse(species!),
        'cohort': cohort,
        'males': number('males'),
        'females': number('females'),
      },
      if (isRep) ...{
        'id': entityId,
        'group': group,
        'technique': c('technique').text.trim(),
      },
      if (step) ...{
        'reproduction': reproduction,
        'kind': widget.kind,
        'parent': parent,
        'quality': quality,
        'quantity': quality == 'UNKNOWN' ? null : number('quantity'),
      },
      if (count || placement) ...{
        'hatch': hatch,
        'quantity': number('quantity'),
        'actually_counted': true,
        'reason': c('reason').text.trim(),
      },
      if (placement) ...{
        'id': entityId,
        'name': c('name').text.trim(),
        'code': c('code').text.trim(),
        if (stage != null) 'stage': stage,
        if (needsConfirmation || recount) ...{
          'confirm_total': number('confirm_total'),
          'confirmation_reason': c('confirmation_reason').text.trim(),
        },
      },
    };
  }

  String get path => cancel
      ? 'breeding-voids/'
      : groupEdit
      ? 'brood-group-revisions/'
      : repEdit
      ? 'reproduction-revisions/'
      : isGroup
      ? 'brood-groups/'
      : isRep
      ? 'reproductions/'
      : placement
      ? 'fry-placements/'
      : count
      ? 'hatch-counts/'
      : 'breeding-facts/';
  Future<void> save() async {
    if (originIdentity != ApiService.sessionIdentity) {
      setState(
        () => error =
            'Session modifiée. Fermez ce formulaire et ouvrez une nouvelle saisie.',
      );
      return;
    }
    if (!uncertain) {
      if (!form.currentState!.validate()) return;
      if ((placement || count) && !actuallyCounted) {
        setState(
          () => error =
              'Confirmez explicitement le comptage réel. Une estimation seule ne devient pas un stock confirmé.',
        );
        return;
      }
    }
    final identity = ApiService.sessionIdentity;
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
            ? breedingError(e)
            : 'Réponse non reçue. Réessayez la même opération : elle ne créera pas deux entrées.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repRows = widget.reproductions
        .where((r) => r['status'] == 'OPEN')
        .map(
          (r) => <String, dynamic>{
            'id': r['id'],
            'name': '${r['group_name']} · ${feedDate(r['occurred_at'])}',
          },
        )
        .toList();
    final hatchRows = widget.facts
        .where(
          (r) =>
              r['kind'] == 'HATCH' &&
              r['canceled'] != true &&
              widget.reproductions.any(
                (rep) =>
                    rep['id'] == r['reproduction'] && rep['status'] == 'OPEN',
              ),
        )
        .map(
          (r) => <String, dynamic>{
            'id': r['id'],
            'name':
                '${feedDate(r['occurred_at'])} · ${r['group_name']} · ${breedingQuality(r['quality'])} (${r['quantity'] ?? '?'})',
          },
        )
        .toList();
    final parentRows = widget.facts
        .where(
          (r) =>
              r['reproduction'] == reproduction &&
              r['canceled'] != true &&
              (widget.kind == 'INCUBATION'
                  ? r['kind'] == 'SPAWN'
                  : ['SPAWN', 'INCUBATION'].contains(r['kind'])),
        )
        .map(
          (r) => <String, dynamic>{
            'id': r['id'],
            'name':
                '${breedingKind(r['kind'])} · ${feedDate(r['occurred_at'])}',
          },
        )
        .toList();
    return Theme(
      data: designSystemV2(Theme.of(context)),
      child: V2AlertDialog(
        backgroundColor: V2Colors.background,
        title: Text(
          isGroup
              ? 'Créer un groupe de géniteurs'
              : groupEdit
              ? 'Actualiser le groupe'
              : repEdit
              ? 'Statut de la reproduction'
              : isRep
              ? 'Enregistrer une reproduction'
              : placement
              ? 'Mettre les alevins en élevage'
              : count
              ? 'Confirmer un comptage'
              : cancel
              ? 'Annuler avec motif'
              : 'Enregistrer ${widget.kind == 'SPAWN'
                    ? 'une ponte'
                    : widget.kind == 'INCUBATION'
                    ? 'une incubation'
                    : 'une éclosion'}',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cancel) ...[
                    Text(
                      'Original conservé : ${breedingKind(widget.initial!['kind'])} · ${widget.initial!['quantity'] ?? 'quantité inconnue'}',
                    ),
                    const Text(
                      'Une entrée en élevage ne peut être compensée que si la cohorte n’a pas été utilisée. Les opérations dépendantes ne sont pas effacées.',
                    ),
                    text('reason', 'Motif de l’annulation', max: 1000),
                  ],
                  if (groupEdit || repEdit) ...[
                    const Text(
                      'La modification est datée, auditée et soumise à la version consultée. Aucun poisson n’est ajouté.',
                    ),
                    select('Statut', status, [
                      for (final v
                          in groupEdit
                              ? ['ACTIVE', 'INACTIVE']
                              : ['OPEN', 'CLOSED'])
                        {
                          'id': v,
                          'name': const {
                            'ACTIVE': 'Actif',
                            'INACTIVE': 'Inactif',
                            'OPEN': 'Ouverte',
                            'CLOSED': 'Clôturée',
                          }[v],
                        },
                    ], (v) => status = v),
                    text('reason', 'Motif de la modification', max: 1000),
                  ],
                  if (isGroup || groupEdit) ...[
                    const Text(
                      'Un groupe décrit des géniteurs existants. Il n’ajoute aucun poisson et ne crée aucune réserve dans une cohorte.',
                    ),
                    text('name', 'Nom du groupe', max: 120),
                    if (isGroup)
                      select('Espèce', species, widget.species, (v) {
                        species = v;
                        cohort = null;
                      }),
                    select(
                      'Installation',
                      site,
                      widget.installations,
                      (v) => site = v,
                    ),
                    if (isGroup)
                      select(
                        'Cohorte d’origine',
                        cohort,
                        widget.cohorts
                            .where(
                              (r) =>
                                  species == null ||
                                  '${r['species']}' == species,
                            )
                            .toList(),
                        (v) => cohort = v,
                        optional: true,
                        empty: 'Origine non renseignée',
                      ),
                    ExpansionTile(
                      maintainState: true,
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Mâles et femelles (facultatif)'),
                      children: [
                        text(
                          'males',
                          'Nombre de mâles',
                          optional: true,
                          integer: true,
                          zero: true,
                        ),
                        text(
                          'females',
                          'Nombre de femelles',
                          optional: true,
                          integer: true,
                          zero: true,
                        ),
                        const Text(
                          'Vide signifie inconnu ; zéro est une valeur explicitement constatée.',
                        ),
                      ],
                    ),
                  ],
                  if (isRep) ...[
                    const Text(
                      'Les étapes biologiques ne sont pas imposées. Cette déclaration ne crée aucun œuf ni poisson.',
                    ),
                    select(
                      'Groupe de géniteurs',
                      group,
                      widget.groups
                          .where((r) => r['status'] == 'ACTIVE')
                          .toList(),
                      (v) {
                        group = v;
                        site = chosenGroup?['installation'] as String?;
                      },
                    ),
                    if (chosenGroup != null)
                      Text('Espèce : ${chosenGroup!['species_name']}'),
                    select(
                      'Installation',
                      site,
                      widget.installations,
                      (v) => site = v,
                    ),
                    ExpansionTile(
                      maintainState: true,
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Technique (facultative)'),
                      children: [
                        text(
                          'technique',
                          'Technique déclarée',
                          optional: true,
                          max: 200,
                        ),
                      ],
                    ),
                  ],
                  if (step) ...[
                    select('Reproduction d’origine', reproduction, repRows, (
                      v,
                    ) {
                      reproduction = v;
                      parent = null;
                      site = chosenRep?['installation'] as String?;
                    }),
                    select(
                      'Installation',
                      site,
                      widget.installations,
                      (v) => site = v,
                    ),
                    if (widget.kind != 'SPAWN')
                      select(
                        'Étape liée (facultative)',
                        parent,
                        parentRows,
                        (v) => parent = v,
                        optional: true,
                        empty: 'Aucune étape préalable renseignée',
                      ),
                    const Text(
                      'Laissez la quantité inconnue si elle n’a pas été mesurée. Une estimation reste une estimation.',
                    ),
                    select(
                      'Qualité de la quantité',
                      quality,
                      [
                        for (final q in ['UNKNOWN', 'ESTIMATED', 'COUNTED'])
                          {'id': q, 'name': breedingQuality(q)},
                      ],
                      (v) {
                        quality = v!;
                        if (v == 'UNKNOWN') c('quantity').clear();
                      },
                    ),
                    if (quality != 'UNKNOWN')
                      text(
                        'quantity',
                        widget.kind == 'HATCH'
                            ? 'Nombre d’alevins observés'
                            : 'Nombre d’œufs',
                        integer: true,
                        zero: true,
                      ),
                    Text(
                      widget.kind == 'HATCH'
                          ? 'L’éclosion ne crée aucun stock vivant. Les alevins entreront en cohorte lors de la mise en élevage.'
                          : 'Les œufs ne sont pas des poissons vivants. Aucun alevin n’en est déduit automatiquement.',
                    ),
                  ],
                  if (count || placement) ...[
                    select('Éclosion d’origine', hatch, hatchRows, (v) {
                      hatch = v;
                      reproduction = chosenHatch?['reproduction'] as String?;
                      recount = false;
                      actuallyCounted = false;
                    }),
                    if (chosenHatch != null) ...[
                      Text(
                        'Observation initiale : ${chosenHatch!['quantity'] ?? 'inconnue'} · ${breedingQuality(chosenHatch!['quality'])}',
                      ),
                      Text(
                        'Confirmés : ${chosenHatch!['availability']?['confirmed_total'] ?? 'inconnu'} · déjà mis en élevage : ${chosenHatch!['availability']?['placed_total'] ?? 0} · disponibles confirmés : ${chosenHatch!['availability']?['available_confirmed'] ?? 'inconnu'}',
                      ),
                    ],
                    select(
                      placement
                          ? 'Installation de destination'
                          : 'Installation du comptage',
                      site,
                      widget.installations,
                      (v) => site = v,
                    ),
                    text(
                      'quantity',
                      placement
                          ? 'Effectif mis en élevage'
                          : 'Effectif total compté',
                      integer: true,
                      zero: count,
                    ),
                    if (count)
                      const Text(
                        'Indiquez le total confirmé du lot d’éclosion, y compris les alevins déjà mis en élevage. Ce comptage n’ajoute aucun poisson vivant.',
                      ),
                    if (placement) ...[
                      text('name', 'Nom de la nouvelle cohorte', max: 120),
                      if (!needsConfirmation)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Renseigner un nouveau comptage total',
                          ),
                          value: recount,
                          onChanged: locked
                              ? null
                              : (v) => setState(() => recount = v!),
                        ),
                      if (needsConfirmation || recount) ...[
                        const Text(
                          'Cette estimation ou quantité inconnue ne suffit pas. Déclarez explicitement un total réellement compté, y compris les quantités déjà affectées.',
                        ),
                        text(
                          'confirm_total',
                          'Total réellement compté',
                          integer: true,
                          zero: true,
                        ),
                        text(
                          'confirmation_reason',
                          'Justification du comptage',
                          max: 1000,
                        ),
                      ],
                      ExpansionTile(
                        maintainState: true,
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Détails de cohorte (facultatif)'),
                        children: [
                          text('code', 'Code de cohorte', max: 50),
                          select(
                            'Stade',
                            stage,
                            widget.stages
                                .where(
                                  (r) => r['species'] == chosenRep?['species'],
                                )
                                .toList(),
                            (v) => stage = v,
                            optional: true,
                          ),
                        ],
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        placement
                            ? 'Je confirme l’effectif réellement compté et mis en élevage'
                            : 'Je confirme un comptage réel, pas une estimation',
                      ),
                      value: actuallyCounted,
                      onChanged: locked
                          ? null
                          : (v) => setState(() => actuallyCounted = v!),
                    ),
                    text(
                      'reason',
                      placement
                          ? 'Motif de la mise en élevage'
                          : 'Justification du comptage',
                      max: placement ? 500 : 1000,
                    ),
                  ],
                  if (!groupEdit && !repEdit) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: locked ? null : date,
                          icon: const Icon(
                            Icons.calendar_month,
                            color: V2Colors.green,
                          ),
                          label: Text(
                            'Date : ${feedDate(at.toIso8601String())}',
                          ),
                        ),
                        if (timeKnown || cancel)
                          OutlinedButton(
                            onPressed: locked ? null : hour,
                            child: Text(
                              'Heure : ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                      ],
                    ),
                    if (!cancel)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Heure connue'),
                        value: timeKnown,
                        onChanged: locked
                            ? null
                            : (v) => setState(() => timeKnown = v!),
                      ),
                    if (!timeKnown && !cancel)
                      const Text(
                        'Date seule conservée. Le début de journée est utilisé pour les contrôles chronologiques ; il doit être compatible avec les événements antérieurs.',
                      ),
                  ],
                  if (!cancel && !repEdit)
                    text('note', 'Note (facultative)', optional: true),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
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
}
