import 'package:flutter/material.dart';
import '../theme/design_system_v2.dart';
import '../widgets/v2_components.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';
import 'feeding_panel.dart'
    show feedCard, feedDate, feedDay, feedWhen, feedDecimal;

const unknownWithdrawal =
    'Délai avant commercialisation non renseigné — vérification nécessaire';
String healthKind(dynamic kind) =>
    kind == 'TREATMENT' ? 'Traitement administré' : 'Observation sanitaire';
String healthProductKey(Map row) => '${row['source']}:${row['id']}';
String healthUnit(dynamic unit) => unit == 'unit'
    ? 'unité'
    : unit == 'dose'
    ? 'dose'
    : '$unit';
String healthProductType(dynamic type) =>
    const {
      'VACCINE': 'Vaccin',
      'TREATMENT': 'Produit de traitement',
      'OTHER': 'Autre produit sanitaire',
    }[type] ??
    '$type';

class HealthPanel extends StatefulWidget {
  const HealthPanel({
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
  });
  final AquaticService service;
  final bool owner;
  final List<String> rights;
  final List<Map<String, dynamic>> installations, cohorts, species;
  final String? initialInstallation, initialCohort, initialAction;
  @override
  State<HealthPanel> createState() => _HealthPanelState();
}

class _HealthPanelState extends State<HealthPanel> {
  Map<String, dynamic>? catalog;
  List<Map<String, dynamic>> history = [], precautions = [];
  bool busy = true, opened = false;
  String? error, site, cohort, species;
  String section = 'current';
  DateTime start = DateTime.now().subtract(const Duration(days: 29)),
      end = DateTime.now();
  int generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.initialAction == 'HISTORY') section = 'history';
    site = widget.initialInstallation;
    cohort = widget.initialCohort;
    load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  String name(dynamic id) =>
      [...widget.installations, ...widget.cohorts]
          .where((r) => '${r['id']}' == '$id')
          .map((r) => '${r['name']}')
          .firstOrNull ??
      'Population non identifiée';
  String query({bool period = true}) =>
      '?${Uri(queryParameters: <String, String>{'installation': ?site, 'cohort': ?cohort, 'species': ?species, if (period) 'from': DateTime(start.year, start.month, start.day).toUtc().toIso8601String(), if (period) 'to': DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toUtc().toIso8601String()}).query}';
  Future<void> load() async {
    final epoch = ++generation, identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
      catalog = null;
      history = [];
      precautions = [];
    });
    try {
      final rows = await Future.wait<dynamic>([
        widget.service.read('health-products/'),
        widget.service.list('health-history/${query()}'),
        widget.service.list('health-state/${query(period: false)}'),
      ]);
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        catalog = rows[0];
        history = rows[1];
        precautions = rows[2];
        busy = false;
      });
      if (!opened &&
          widget.initialAction != null &&
          widget.initialAction != 'HISTORY') {
        opened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) edit(widget.initialAction!);
        });
      }
    } catch (_) {
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        busy = false;
        error =
            'Suivi sanitaire indisponible. Vérifiez la connexion et vos droits, puis actualisez.';
      });
    }
  }

  Future<void> edit(String kind, {Map<String, dynamic>? initial}) async {
    final identity = ApiService.sessionIdentity;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HealthEditor(
        service: widget.service,
        kind: kind,
        catalog: catalog!,
        owner: widget.owner,
        installations: widget.installations,
        cohorts: widget.cohorts,
        initialInstallation: site,
        initialCohort: cohort,
        initial: initial,
      ),
    );
    if (changed == true && mounted && identity == ApiService.sessionIdentity) {
      await load();
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

  Widget record(Map<String, dynamic> row) => feedCard([
    Text(
      healthKind(row['kind']),
      style: const TextStyle(fontWeight: FontWeight.bold, color: V2Colors.navy),
    ),
    Text('${feedWhen(row)} · ${name(row['installation'])}'),
    Text(
      row['cohort'] == null
          ? 'Bassin global · populations présentes à la date conservées'
          : 'Cohorte : ${name(row['cohort'])}',
    ),
    if (row['kind'] == 'OBSERVATION') ...[
      if ('${row['symptoms'] ?? ''}'.isNotEmpty)
        Text('Symptômes : ${row['symptoms']}'),
      if ('${row['behavior'] ?? ''}'.isNotEmpty)
        Text('Comportement : ${row['behavior']}'),
    ] else ...[
      Text(
        '${(row['product_snapshot'] as Map?)?['name']} · ${row['quantity']} ${healthUnit(row['unit'])} administrés',
      ),
      Text('Motif : ${row['reason']}'),
      Text(
        row['ongoing'] == true
            ? 'Traitement en cours (déclaré)'
            : 'Acte administré enregistré',
      ),
      if (row['observation'] != null)
        const Text('Lié à une observation sanitaire conservée'),
      if (row['withdrawal_days'] == null)
        const Text(
          unknownWithdrawal,
          style: TextStyle(fontWeight: FontWeight.bold, color: V2Colors.navy),
        )
      else ...[
        Text(
          'Délai documenté : ${row['withdrawal_days']} jour(s) · ${row['precaution']?['message'] ?? ''}',
        ),
        Text(
          'Fin calculée : ${row['precaution']?['end_date'] ?? feedWhen({'occurred_at': row['withdrawal_until']})}',
        ),
        Text('Source : ${row['withdrawal_source']}'),
        if (row['time_precision'] == 'DATE')
          const Text('Heure inconnue : fin de journée retenue par précaution.'),
      ],
    ],
    if ('${row['note'] ?? ''}'.isNotEmpty) Text('Note : ${row['note']}'),
    Text(
      'Auteur : ${row['actor_name'] ?? row['actor']} · enregistré le ${feedDate(row['recorded_at'])}',
    ),
    if (row['supersedes'] != null)
      Text('Rectification : ${row['correction_reason']}'),
    if (row['is_current'] == false)
      const Text(
        'Original conservé · rectifié par un enregistrement ultérieur',
      ),
    if (widget.owner && row['is_current'] != false)
      TextButton.icon(
        onPressed: busy ? null : () => edit('${row['kind']}', initial: row),
        icon: const Icon(Icons.edit_note, color: V2Colors.green),
        label: const Text('Rectifier avec motif'),
      ),
  ]);
  @override
  Widget build(BuildContext context) => Theme(
    data: designSystemV2(Theme.of(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Santé',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: V2Colors.navy,
          ),
        ),
        const Text(
          'Décrivez ce que vous constatez. Aucun diagnostic n’est demandé et aucun décès n’est déduit automatiquement.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.rights.contains('aquatic.health.observe'))
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: V2Colors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy || catalog == null
                    ? null
                    : () => edit('OBSERVATION'),
                icon: const Icon(
                  Icons.health_and_safety,
                  color: V2Colors.green,
                ),
                label: const Text('Signaler un problème'),
              ),
            if (widget.rights.contains('aquatic.health.treat'))
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: V2Colors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy || catalog == null
                    ? null
                    : () => edit('TREATMENT'),
                icon: const Icon(Icons.medical_services, color: V2Colors.green),
                label: const Text('Enregistrer un traitement'),
              ),
            OutlinedButton.icon(
              onPressed: () => setState(() => section = 'history'),
              icon: const Icon(Icons.history, color: V2Colors.green),
              label: const Text('Consulter l’historique'),
            ),
            OutlinedButton(
              onPressed: busy ? null : load,
              child: const Text('Actualiser'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            filter('Bassin', site, widget.installations, (v) {
              site = v;
              cohort = null;
            }),
            filter('Cohorte', cohort, widget.cohorts, (v) => cohort = v),
            filter('Espèce', species, widget.species, (v) => species = v),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const {
              'current': 'En cours et précautions',
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
                onSelected: (_) => setState(() => section = entry.key),
              ),
            if (widget.owner && catalog?['can_manage'] == true)
              OutlinedButton(
                onPressed: () => edit('PRODUCT'),
                child: const Text('Ajouter un produit au référentiel'),
              ),
          ],
        ),
        if (section == 'current') ...[
          const Text(
            'Précautions actuelles : toutes dates, indépendantes de la période de l’historique. Après un transfert ou un mélange, les populations concernées doivent être vérifiées.',
          ),
          const Text(
            'Aucun résultat de cet écran ne constitue une autorisation de vente.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (!busy && error == null && precautions.isEmpty)
            const Text(
              'Aucun traitement en cours ni précaution ouverte enregistré pour ces filtres. Vérifiez les informations disponibles avant commercialisation.',
            ),
          for (final row in precautions) record(row),
        ] else ...[
          OutlinedButton.icon(
            onPressed: busy ? null : period,
            icon: const Icon(Icons.date_range, color: V2Colors.green),
            label: Text(
              'Période : ${feedDate(start.toIso8601String())} au ${feedDate(end.toIso8601String())}',
            ),
          ),
          const Text(
            'Les actes au bassin restent globaux ; un filtre de cohorte ou d’espèce affiche les actes qui concernaient ses populations à la date, sans répartir les doses.',
          ),
          if (!busy && error == null && history.isEmpty)
            const Text('Aucun événement sanitaire pour ces filtres.'),
          for (final row in history.reversed) record(row),
        ],
        const Text(
          'Stock sanitaire non déduit automatiquement. Aucune nouvelle dépense. Les décès constatés restent à enregistrer dans Pertes et inventaires.',
        ),
      ],
    ),
  );
}

class HealthEditor extends StatefulWidget {
  const HealthEditor({
    super.key,
    required this.service,
    required this.kind,
    required this.catalog,
    required this.owner,
    required this.installations,
    required this.cohorts,
    this.initialInstallation,
    this.initialCohort,
    this.initial,
  });
  final AquaticService service;
  final String kind;
  final Map<String, dynamic> catalog;
  final bool owner;
  final List<Map<String, dynamic>> installations, cohorts;
  final String? initialInstallation, initialCohort;
  final Map<String, dynamic>? initial;
  @override
  State<HealthEditor> createState() => _HealthEditorState();
}

class _HealthEditorState extends State<HealthEditor> {
  final originIdentity = ApiService.sessionIdentity;
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  TextEditingController c(String key) =>
      fields.putIfAbsent(key, () => TextEditingController());
  String? site, cohort, product, observation, productType, unit;
  List<Map<String, dynamic>> observations = [];
  DateTime at = DateTime.now();
  bool busy = false,
      uncertain = false,
      timeKnown = true,
      ongoing = false,
      documented = false,
      administered = false,
      loadingObservations = false;
  String? error;
  Map<String, dynamic>? pending;
  int observationGeneration = 0;
  bool get isProduct => widget.kind == 'PRODUCT';
  bool get treatment => widget.kind == 'TREATMENT';
  bool get correction => widget.initial != null;
  bool get locked => busy || uncertain;
  List<Map<String, dynamic>> get products =>
      List<Map<String, dynamic>>.from(widget.catalog['products'] as List)
          .where(
            (r) =>
                r['archived'] != true ||
                (correction && healthProductKey(r) == product),
          )
          .toList();
  Map<String, dynamic>? get selected =>
      products.where((r) => healthProductKey(r) == product).firstOrNull;
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    site = initial?['installation'] as String? ?? widget.initialInstallation;
    cohort = initial?['cohort'] as String? ?? widget.initialCohort;
    if (site == null && cohort != null) {
      final row = widget.cohorts.where((r) => r['id'] == cohort).firstOrNull;
      final positions = row?['positions'] as List? ?? [];
      if (positions.length == 1) site = '${positions.first['installation']}';
    }
    if (initial != null) {
      at = DateTime.tryParse('${initial['occurred_at']}')?.toLocal() ?? at;
      timeKnown = initial['time_precision'] != 'DATE';
      if (!timeKnown && initial['business_date'] != null) {
        at = DateTime.parse('${initial['business_date']}');
      }
      for (final key in [
        'symptoms',
        'behavior',
        'note',
        'quantity',
        'reason',
        'withdrawal_source',
      ]) {
        c(key).text = '${initial[key] ?? ''}';
      }
      ongoing = initial['ongoing'] == true;
      documented = initial['withdrawal_days'] != null;
      c('withdrawal_days').text = '${initial['withdrawal_days'] ?? ''}';
      final snapshot = initial['product_snapshot'] as Map?;
      if (snapshot != null && snapshot.isNotEmpty) {
        product = healthProductKey(snapshot);
      }
      observation = initial['observation'] as String?;
    }
    if (treatment && site != null) loadObservations();
  }

  @override
  void dispose() {
    observationGeneration++;
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> loadObservations() async {
    final epoch = ++observationGeneration,
        identity = ApiService.sessionIdentity;
    setState(() {
      loadingObservations = true;
      observations = [];
    });
    if (site == null) {
      setState(() => loadingObservations = false);
      return;
    }
    try {
      final rows = await widget.service.list(
        'health-observations/?${Uri(queryParameters: {'installation': site!}).query}',
      );
      if (!mounted ||
          epoch != observationGeneration ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        observations = rows
            .where((r) => r['is_current'] != false || r['id'] == observation)
            .toList();
        loadingObservations = false;
      });
    } catch (_) {
      if (!mounted ||
          epoch != observationGeneration ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        loadingObservations = false;
        error =
            'Observations associées indisponibles. Vous pouvez enregistrer un traitement sans lien.';
      });
    }
  }

  Widget text(
    String key,
    String label, {
    bool optional = false,
    int max = 2000,
    bool decimal = false,
    int scale = 6,
    bool integer = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: c(key),
      enabled: !locked,
      maxLength: decimal || integer ? null : max,
      minLines: 1,
      maxLines: decimal || integer ? 1 : 3,
      keyboardType: decimal || integer
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.multiline,
      decoration: V2InputDecoration(labelText: label),
      validator: (value) {
        final v = (value ?? '').trim();
        if (v.isEmpty) return optional ? null : 'Champ requis';
        if (integer && !RegExp(r'^[0-9]+$').hasMatch(v)) {
          return 'Nombre entier de jours requis';
        }
        if (decimal) {
          final n = feedDecimal(v);
          if (!RegExp('^[0-9]+(?:[.][0-9]{1,$scale})?\u0024').hasMatch(n)) {
            return 'Nombre décimal positif, $scale chiffres après la virgule au maximum';
          }
          if (BigInt.parse(n.replaceAll('.', '')) == BigInt.zero) {
            return 'Quantité strictement positive';
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
      initialValue: rows.any((r) => '${r['id']}' == value) ? value : null,
      isExpanded: true,
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
    final value = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (value != null && mounted) {
      setState(
        () => at = DateTime(
          value.year,
          value.month,
          value.day,
          at.hour,
          at.minute,
        ),
      );
    }
  }

  Future<void> hour() async {
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
    );
    if (value != null && mounted) {
      setState(
        () =>
            at = DateTime(at.year, at.month, at.day, value.hour, value.minute),
      );
    }
  }

  Map<String, dynamic> moment() {
    if (timeKnown) {
      return {
        'occurred_at': at.toUtc().toIso8601String(),
        'time_precision': 'DATETIME',
      };
    }
    final d = DateTime(at.year, at.month, at.day),
        offset = d.timeZoneOffset,
        mins = offset.inMinutes.abs();
    return {
      'occurred_at':
          '${feedDay(d)}T00:00:00${offset.isNegative ? '-' : '+'}${(mins ~/ 60).toString().padLeft(2, '0')}:${(mins % 60).toString().padLeft(2, '0')}',
      'time_precision': 'DATE',
      'business_date': feedDay(d),
    };
  }

  Map<String, dynamic> payload() {
    if (isProduct) {
      return {
        'id': widget.service.command({})['operation_uuid'],
        'name': c('name').text.trim(),
        'type': productType,
        'unit': unit,
        'information': c('information').text.trim(),
      };
    }
    return {
      ...moment(),
      'installation': site,
      'cohort': cohort,
      'note': c('note').text.trim(),
      if (!treatment) ...{
        'symptoms': c('symptoms').text.trim(),
        'behavior': c('behavior').text.trim(),
      } else ...{
        selected!['source'] == 'SUPPLY' ? 'supply_product' : 'sanitary_product':
            selected!['id'],
        'quantity': feedDecimal(c('quantity').text),
        'unit': selected!['unit'],
        'reason': c('reason').text.trim(),
        'administration_status': 'ADMINISTERED',
        'ongoing': ongoing,
        'observation': observation,
        'withdrawal_days': documented
            ? int.parse(c('withdrawal_days').text.trim())
            : null,
        'withdrawal_source': documented
            ? c('withdrawal_source').text.trim()
            : '',
      },
    };
  }

  Future<void> save() async {
    if (originIdentity != ApiService.sessionIdentity) {
      setState(() {
        busy = false;
        error =
            'Session modifiée. Fermez ce formulaire et ouvrez une nouvelle saisie.';
      });
      return;
    }
    if (!uncertain) {
      if (!form.currentState!.validate()) return;
      if (!isProduct &&
          !treatment &&
          c('symptoms').text.trim().isEmpty &&
          c('behavior').text.trim().isEmpty) {
        setState(
          () => error =
              'Décrivez au moins un symptôme ou un comportement observé.',
        );
        return;
      }
      if (treatment && !administered) {
        setState(
          () => error =
              'Confirmez que ce traitement a effectivement été administré.',
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
      final fields = payload();
      pending ??= widget.service.command(
        correction
            ? {
                'target': widget.initial!['id'],
                'reason': c('correction_reason').text.trim(),
                treatment ? 'treatment' : 'observation': fields,
              }
            : fields,
      );
      await widget.service.send(
        correction
            ? 'health-corrections/'
            : isProduct
            ? 'health-products/'
            : treatment
            ? 'health-treatments/'
            : 'health-observations/',
        pending!,
      );
      if (!mounted || identity != ApiService.sessionIdentity) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted || identity != ApiService.sessionIdentity) return;
      final deterministic =
          e is ApiHttpException &&
          e.status >= 400 &&
          e.status < 500 &&
          e.status != 408;
      setState(() {
        busy = false;
        uncertain = !deterministic;
        if (deterministic) pending = null;
        error = deterministic
            ? 'Enregistrement refusé. Vérifiez la date, les références et vos droits. ${e.message}'
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
        correction
            ? 'Rectifier ${treatment ? 'le traitement' : 'l’observation'}'
            : isProduct
            ? 'Ajouter un produit sanitaire'
            : treatment
            ? 'Enregistrer un traitement'
            : 'Signaler un problème de santé',
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (correction) ...[
                  const Text(
                    'L’original sera conservé. La rectification complète le remplace pour les précautions actuelles.',
                  ),
                  text(
                    'correction_reason',
                    'Motif de la rectification',
                    max: 1000,
                  ),
                ],
                if (isProduct) ...[
                  const Text(
                    'Vérifiez le référentiel existant avant d’ajouter un produit. Les vaccins existants sont déjà disponibles. Aucun achat ni traitement n’est créé ici.',
                  ),
                  text('name', 'Nom du produit', max: 120),
                  select('Type de produit', productType, const [
                    {'id': 'TREATMENT', 'name': 'Produit de traitement'},
                    {'id': 'OTHER', 'name': 'Autre produit sanitaire'},
                  ], (v) => productType = v),
                  select('Unité d’administration', unit, [
                    for (final u in ['dose', 'mL', 'L', 'g', 'kg', 'unit'])
                      {'id': u, 'name': healthUnit(u)},
                  ], (v) => unit = v),
                  text(
                    'information',
                    'Informations utiles (facultatif)',
                    optional: true,
                    max: 1000,
                  ),
                ] else ...[
                  Text(
                    treatment
                        ? 'Enregistrez uniquement un acte déjà administré, jamais un soin prévu. Aucune dépense ni déduction de stock sanitaire automatique.'
                        : 'Décrivez les faits observés, sans diagnostic obligatoire. Les mortalités constatées se saisissent dans Pertes et inventaires.',
                  ),
                  const SizedBox(height: 12),
                  select('Bassin concerné', site, widget.installations, (v) {
                    site = v;
                    observation = null;
                    if (treatment) loadObservations();
                  }),
                  select(
                    'Cohorte (facultative)',
                    cohort,
                    widget.cohorts,
                    (v) => cohort = v,
                    optional: true,
                    empty: 'Bassin global',
                  ),
                  const Text(
                    'Sans cohorte identifiée, l’observation ou le traitement reste global au bassin. Les populations présentes à la date sont conservées.',
                  ),
                  if (!treatment) ...[
                    text('symptoms', 'Symptômes observés', optional: true),
                    text(
                      'behavior',
                      'Comportement des poissons',
                      optional: true,
                    ),
                    const Text(
                      'Au moins une description est nécessaire. Photo facultative non disponible : stockage privé adapté non configuré.',
                    ),
                  ] else ...[
                    select('Produit utilisé', product, [
                      for (final r in products)
                        {
                          'id': healthProductKey(r),
                          'name':
                              '${r['name']} · ${healthProductType(r['type'])} · ${healthUnit(r['unit'])}',
                        },
                    ], (v) => product = v),
                    if (selected != null) ...[
                      Text('Unité : ${healthUnit(selected!['unit'])}'),
                      if ('${selected!['information'] ?? ''}'.isNotEmpty)
                        Text('${selected!['information']}'),
                    ],
                    text('quantity', 'Quantité administrée', decimal: true),
                    text('reason', 'Motif du traitement', max: 1000),
                    if (loadingObservations) const LinearProgressIndicator(),
                    select(
                      'Observation liée',
                      observation,
                      [
                        for (final r in observations)
                          {
                            'id': r['id'],
                            'name':
                                '${feedDate(r['occurred_at'])} · ${r['symptoms'] ?? r['behavior']}',
                          },
                      ],
                      (v) => observation = v,
                      optional: true,
                      empty: 'Sans observation préalable',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Traitement en cours (déclaration)'),
                      value: ongoing,
                      onChanged: locked
                          ? null
                          : (v) => setState(() => ongoing = v!),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Délai avant commercialisation connu et documenté',
                      ),
                      value: documented,
                      onChanged: locked
                          ? null
                          : (v) => setState(() => documented = v!),
                    ),
                    if (documented) ...[
                      text(
                        'withdrawal_days',
                        'Délai documenté (jours)',
                        integer: true,
                      ),
                      text('withdrawal_source', 'Source du délai', max: 1000),
                    ] else
                      const Text(
                        unknownWithdrawal,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: V2Colors.navy,
                        ),
                      ),
                    const Text(
                      'Aucun délai recommandé automatiquement. Le suivi ne constitue pas une autorisation de vente.',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Je confirme que le traitement a été administré',
                      ),
                      value: administered,
                      onChanged: locked
                          ? null
                          : (v) => setState(() => administered = v!),
                    ),
                  ],
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
                        label: Text('Date : ${feedDate(at.toIso8601String())}'),
                      ),
                      if (timeKnown)
                        OutlinedButton(
                          onPressed: locked ? null : hour,
                          child: Text(
                            'Heure : ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                          ),
                        ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Heure connue'),
                    value: timeKnown,
                    onChanged: locked
                        ? null
                        : (v) => setState(() => timeKnown = v!),
                  ),
                  if (!timeKnown)
                    const Text(
                      'Date seule conservée. Le début de journée sert au contrôle de présence ; pour un délai documenté, la fin de journée est retenue par précaution.',
                    ),
                  text('note', 'Note (facultative)', optional: true),
                ],
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
