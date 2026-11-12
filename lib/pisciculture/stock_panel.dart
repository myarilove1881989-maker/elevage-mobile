import 'package:flutter/material.dart';
import '../widgets/v2_components.dart';
import '../theme/design_system_v2.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';

String stockKindLabel(dynamic kind) =>
    const {
      'MORTALITY': 'Mortalité confirmée',
      'SUSPICION': 'Suspicion (sans déduction)',
      'RECONCILE': 'Rapprochement',
      'INVENTORY': 'Inventaire',
      'ASSIGN_CREDIT': 'Affectation de crédit',
      'CANCEL': 'Annulation compensatoire',
    }[kind] ??
    '$kind';

class StockPanel extends StatefulWidget {
  const StockPanel({
    super.key,
    required this.service,
    required this.owner,
    required this.rights,
    required this.installations,
    required this.cohorts,
    this.onChanged,
  });
  final AquaticService service;
  final bool owner;
  final List<String> rights;
  final List<Map<String, dynamic>> installations, cohorts;
  final Future<void> Function()? onChanged;
  @override
  State<StockPanel> createState() => _StockPanelState();
}

class _StockPanelState extends State<StockPanel> {
  Map<String, dynamic>? data;
  List<Map<String, dynamic>> history = [];
  bool busy = true;
  String? error, installation, cohort;
  String section = 'pending';
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  String name(dynamic id) =>
      [...widget.cohorts, ...widget.installations]
          .where((r) => r['id'] == id)
          .map((r) => r['name'].toString())
          .firstOrNull ??
      '$id';
  Future<void> load() async {
    final epoch = ++generation, identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
      data = null;
      history = [];
    });
    try {
      final query = Uri(
        queryParameters: <String, String>{
          'installation': ?installation,
          'cohort': ?cohort,
        },
      ).query;
      final suffix = query.isEmpty ? '' : '?$query';
      final result = await Future.wait<dynamic>([
        widget.service.read('stock-state/$suffix'),
        widget.service.list('stock-history/$suffix'),
      ]);
      if (!mounted ||
          generation != epoch ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        data = result[0] as Map<String, dynamic>;
        history = result[1] as List<Map<String, dynamic>>;
        busy = false;
      });
    } catch (_) {
      if (!mounted ||
          generation != epoch ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        busy = false;
        error =
            'Effectifs indisponibles. Actualisez après vérification de la connexion et des droits.';
        data = null;
        history = [];
      });
    }
  }

  Future<void> edit(String kind, [Map<String, dynamic>? target]) async {
    final identity = ApiService.sessionIdentity;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockEditor(
        service: widget.service,
        kind: kind,
        state: data!,
        installations: widget.installations
            .where((r) => installation == null || r['id'] == installation)
            .toList(),
        cohorts: widget.cohorts,
        target: target,
      ),
    );
    if (changed == true && mounted && identity == ApiService.sessionIdentity) {
      await load();
      if (!mounted || identity != ApiService.sessionIdentity) return;
      await widget.onChanged?.call();
    }
  }

  Widget choice(
    String label,
    String? value,
    List<Map<String, dynamic>> rows,
    ValueChanged<String?> change,
  ) => SizedBox(
    width: 270,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      isExpanded: true,
      initialValue: value,
      decoration: V2InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: null, child: Text('Tous')),
        ...rows.map(
          (r) => DropdownMenuItem(
            value: r['id'] as String,
            child: Text(r['name'].toString(), overflow: TextOverflow.ellipsis),
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
  Widget card(List<Widget> children) => Card(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: V2Colors.navy),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Mortalités, rapprochement et inventaires',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Les mortalités confirmées et les écarts d’inventaire restent distincts. Une suspicion ne retire aucun poisson.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: V2Colors.navy,
              side: const BorderSide(color: V2Colors.navy),
            ),
            onPressed: busy ? null : load,
            child: const Text('Actualiser les effectifs'),
          ),
          if (widget.rights.contains('aquatic.losses.create'))
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: V2Colors.navy,
                foregroundColor: Colors.white,
              ),
              onPressed: busy || error != null ? null : () => edit('MORTALITY'),
              child: const Text('Enregistrer une mortalité'),
            ),
          if (widget.owner)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: V2Colors.navy,
                foregroundColor: Colors.white,
              ),
              onPressed: busy || error != null ? null : () => edit('INVENTORY'),
              child: const Text('Réaliser un inventaire'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          choice(
            'Installation',
            installation,
            widget.installations,
            (v) => installation = v,
          ),
          choice('Cohorte', cohort, widget.cohorts, (v) => cohort = v),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      if (data != null) ...[
        const SizedBox(height: 12),
        if (cohort == null)
          Text(
            'Vivants : ${data!['live_count']} · Pertes en attente : ${data!['unassigned_losses']} · Crédits non affectés : ${data!['unassigned_credits']}',
          ),
        if (cohort != null)
          Text(
            'Cohorte : brut ${data!['cohort_count']['gross']} · plage ${data!['cohort_count']['lower']} à ${data!['cohort_count']['upper']} · ${data!['cohort_count']['quality']}',
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: V2Colors.navy),
              onPressed: () => setState(() => section = 'pending'),
              child: const Text('Pertes et crédits en attente'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: V2Colors.navy),
              onPressed: () => setState(() => section = 'history'),
              child: const Text('Historique des corrections'),
            ),
          ],
        ),
        if (section == 'pending') ...[
          for (final row in data!['pending'] as List)
            card([
              Text(
                '${stockKindLabel(row['kind'])} · ${name(row['installation'])}',
              ),
              Text(
                'À rapprocher : ${row['remaining']} sur ${row['quantity']} poissons',
              ),
              Text('Constaté le ${row['occurred_at']}'),
              Text(
                'Cohortes éligibles : ${(row['eligible'] as List).map(name).join(', ')}',
              ),
              if (widget.owner)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: V2Colors.navy),
                  onPressed: () =>
                      edit('RECONCILE', Map<String, dynamic>.from(row as Map)),
                  child: const Text('Rapprocher cette perte'),
                ),
            ]),
          for (final row in data!['credits'] as List)
            card([
              Text('Crédit d’inventaire · ${name(row['installation'])}'),
              Text(
                '${row['remaining']} poissons non affectés — non transférables',
              ),
              if (widget.owner)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: V2Colors.navy),
                  onPressed: () => edit(
                    'ASSIGN_CREDIT',
                    Map<String, dynamic>.from(row as Map),
                  ),
                  child: const Text('Affecter ce crédit'),
                ),
            ]),
          if ((data!['pending'] as List).isEmpty &&
              (data!['credits'] as List).isEmpty)
            const Text('Aucune perte ni crédit en attente.'),
          const SizedBox(height: 12),
          const Text('Disponibilités conservatrices par cohorte'),
          for (final row in data!['positions'] as List)
            Text(
              '${row['cohort_name']} · ${row['installation_name']} : brut ${row['gross_count']}, réservé ${row['reserved_count']}, disponible ${row['available_count']}',
            ),
          if (!widget.owner)
            const Text(
              'Les rapprochements et corrections sensibles sont réservés au propriétaire.',
            ),
        ] else ...[
          for (final row in history)
            card([
              Text(
                '${stockKindLabel(row['kind'])} · ${name(row['installation'])}',
              ),
              Text(
                '${row['occurred_at']} · ${row['quantity']} poissons · Auteur ${row['actor']}',
              ),
              if (row['cohort'] != null)
                Text('Cohorte : ${name(row['cohort'])}'),
              Text('Motif : ${row['reason']}'),
              if (row['note'] != '') Text('${row['note']}'),
              if (row['kind'] == 'INVENTORY')
                Text(
                  'Constat : ${row['payload']['observed_count']} · théorique avant : ${row['payload']['before_live_count']} · écart : ${row['payload']['delta']}',
                ),
              if (row['kind'] == 'RECONCILE')
                for (final a in row['payload']['allocations'] as List)
                  Text(
                    '${name(a['cohort'])} : ${a['quantity']} poissons rapprochés',
                  ),
              if (row['kind'] == 'CANCEL')
                Text('Compensation du fait ${row['reverses']}'),
              if (row['canceled'] == true)
                const Text(
                  'Annulé par un événement compensatoire — original conservé',
                ),
              if (widget.owner &&
                  row['kind'] != 'CANCEL' &&
                  row['canceled'] != true &&
                  (row['quantity'] as num) > 0)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: V2Colors.navy),
                  onPressed: () => edit('CANCEL', row),
                  child: const Text('Annuler par compensation'),
                ),
            ]),
          if (history.isEmpty)
            const Text('Aucun événement de mortalité ou d’inventaire.'),
        ],
      ],
    ],
  );
}

class StockEditor extends StatefulWidget {
  const StockEditor({
    super.key,
    required this.service,
    required this.kind,
    required this.state,
    required this.installations,
    required this.cohorts,
    this.target,
  });
  final AquaticService service;
  final String kind;
  final Map<String, dynamic> state;
  final List<Map<String, dynamic>> installations, cohorts;
  final Map<String, dynamic>? target;
  @override
  State<StockEditor> createState() => _StockEditorState();
}

class _StockEditorState extends State<StockEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String? installation, cohort;
  bool suspected = false, busy = false, uncertain = false;
  String? error, pendingPath;
  Map<String, dynamic>? pending;
  TextEditingController c(String key, [String initial = '']) =>
      fields.putIfAbsent(key, () => TextEditingController(text: initial));
  @override
  void initState() {
    super.initState();
    installation =
        widget.target?['installation'] as String? ??
        widget.installations.firstOrNull?['id'] as String?;
    c('at', DateTime.now().toUtc().toIso8601String());
  }

  @override
  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  String name(dynamic id) =>
      [...widget.cohorts, ...widget.installations]
          .where((r) => r['id'] == id)
          .map((r) => r['name'].toString())
          .firstOrNull ??
      '$id';
  Widget integer(
    String key,
    String label, {
    bool zero = false,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c(key),
      enabled: !busy && !uncertain,
      keyboardType: TextInputType.number,
      decoration: V2InputDecoration(labelText: label),
      validator: (v) {
        final text = (v ?? '').trim();
        if (optional && text.isEmpty) return null;
        final n = int.tryParse(text);
        return !RegExp(r'^[0-9]+$').hasMatch(text) ||
                n == null ||
                n < (zero ? 0 : 1)
            ? 'Nombre entier ${zero ? 'positif ou nul' : 'strictement positif'} requis'
            : null;
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
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      isExpanded: true,
      initialValue: value,
      decoration: V2InputDecoration(labelText: label),
      items: [
        if (optional)
          const DropdownMenuItem(value: null, child: Text('Non identifiée')),
        ...rows.map(
          (r) => DropdownMenuItem(
            value: r['id'] as String,
            child: Text(r['name'].toString(), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: busy || uncertain ? null : change,
      validator: (v) => v == null && !optional ? 'Sélection requise' : null,
    ),
  );
  Future<void> save() async {
    if (!uncertain) {
      if (!form.currentState!.validate()) return;
      final body = <String, dynamic>{
        'occurred_at': DateTime.parse(c('at').text).toUtc().toIso8601String(),
        'reason': c('reason').text.trim(),
        'note': c('note').text.trim(),
      };
      switch (widget.kind) {
        case 'MORTALITY':
          pendingPath = 'mortalities/';
          body.addAll({
            'installation': installation,
            'quantity': int.parse(c('quantity').text),
            'suspected': suspected,
          });
          if (cohort != null) body['cohort'] = cohort;
        case 'RECONCILE':
          pendingPath = 'loss-reconciliations/';
          body['pending'] = widget.target!['id'];
          final allocations = <Map<String, dynamic>>[];
          for (final id in widget.target!['eligible'] as List) {
            final text = c('allocation:$id').text.trim();
            if (text.isNotEmpty) {
              allocations.add({'cohort': id, 'quantity': int.parse(text)});
            }
          }
          if (allocations.isEmpty) {
            setState(() => error = 'Renseignez au moins une attribution.');
            return;
          }
          body['allocations'] = allocations;
        case 'INVENTORY':
          pendingPath = 'inventories/';
          body.addAll({
            'installation': installation,
            'observed_count': int.parse(c('observed_count').text),
            'expected_revision': widget.state['business_revision'],
          });
        case 'ASSIGN_CREDIT':
          pendingPath = 'inventory-credits/assign/';
          body.addAll({
            'credit': widget.target!['id'],
            'cohort': cohort,
            'quantity': int.parse(c('quantity').text),
          });
        case 'CANCEL':
          pendingPath = 'stock-cancellations/';
          body['target'] = widget.target!['id'];
      }
      pending = widget.service.command(body);
    }
    final identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.send(pendingPath!, pending!);
      if (!mounted || identity != ApiService.sessionIdentity) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted || identity != ApiService.sessionIdentity) return;
      final ambiguous = e is! ApiHttpException || e.status >= 500;
      setState(() {
        busy = false;
        uncertain = ambiguous;
        error = ambiguous
            ? 'Réponse incertaine. Réessayez la même opération, sans créer de doublon.'
            : e.status == 409
            ? 'Conflit d’effectifs ou de chronologie : ${e.message}. Actualisez les données avant de reprendre.'
            : 'Opération refusée : ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.cohorts.where((r) => r['status'] == 'OPEN').toList();
    final presentIds = (widget.state['positions'] as List? ?? [])
        .where((p) => p['installation'] == installation)
        .map((p) => p['cohort'])
        .toSet();
    final current =
        (widget.state['installations'] as List? ?? [])
                .where((r) => r['id'] == installation)
                .firstOrNull
            as Map?;
    return PopScope(
      canPop: !busy && !uncertain,
      child: V2AlertDialog(
        title: Text(stockKindLabel(widget.kind)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (['MORTALITY', 'INVENTORY'].contains(widget.kind))
                    select(
                      'Installation',
                      installation,
                      widget.installations,
                      (v) => setState(() {
                        installation = v;
                        cohort = null;
                      }),
                    ),
                  if (widget.kind == 'MORTALITY') ...[
                    select(
                      'Cohorte (si connue)',
                      cohort,
                      open.where((r) => presentIds.contains(r['id'])).toList(),
                      (v) => setState(() => cohort = v),
                      optional: true,
                    ),
                    integer('quantity', 'Nombre de poissons concernés'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Simple suspicion — aucune déduction'),
                      value: suspected,
                      onChanged: busy || uncertain
                          ? null
                          : (v) => setState(() => suspected = v),
                    ),
                    const Text(
                      'Sans cohorte identifiée, la mortalité confirmée diminue le vivant du bassin et reste à rapprocher.',
                    ),
                  ],
                  if (widget.kind == 'RECONCILE') ...[
                    Text(
                      'Installation : ${name(widget.target!['installation'])} · à rapprocher : ${widget.target!['remaining']}',
                    ),
                    const Text(
                      'Une attribution partielle est possible. Le total vivant ne sera pas diminué une seconde fois.',
                    ),
                    for (final id in widget.target!['eligible'] as List)
                      integer(
                        'allocation:$id',
                        'Attribution à ${name(id)}',
                        optional: true,
                      ),
                  ],
                  if (widget.kind == 'INVENTORY') ...[
                    Text(
                      'Théorique vivant actuel : ${current?['live_count'] ?? 'Inconnu'}',
                    ),
                    Text(
                      'Brut : ${current?['gross_count'] ?? '—'} · pertes en attente : ${current?['pending_count'] ?? '—'} · crédits non affectés : ${current?['unassigned_credit'] ?? '—'}',
                    ),
                    integer(
                      'observed_count',
                      'Nombre réellement constaté',
                      zero: true,
                    ),
                    const Text(
                      'Un écart négatif devient une correction à rapprocher, distincte des mortalités. Un écart positif reste non transférable avant affectation. Pour une date passée, le calcul utilise l’effectif historique à cette date.',
                    ),
                    const Text(
                      'Si un crédit reste non affecté, affectez-le ou annulez-le avant un nouvel inventaire différent.',
                    ),
                  ],
                  if (widget.kind == 'ASSIGN_CREDIT') ...[
                    Text(
                      'Crédit non affecté : ${widget.target!['remaining']} poissons · ${name(widget.target!['installation'])}',
                    ),
                    select(
                      'Cohorte destinataire',
                      cohort,
                      open,
                      (v) => setState(() => cohort = v),
                    ),
                    integer('quantity', 'Nombre à affecter'),
                    const Text(
                      'L’affectation conserve le total vivant ; elle rend ces poissons disponibles dans la cohorte choisie.',
                    ),
                  ],
                  if (widget.kind == 'CANCEL') ...[
                    Text(
                      'Original conservé : ${stockKindLabel(widget.target!['kind'])} · ${widget.target!['quantity']} poissons',
                    ),
                    const Text(
                      'Une compensation datée sera ajoutée. Les rapprochements ou affectations dépendants doivent être annulés en premier.',
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: c('at'),
                    enabled: !busy && !uncertain,
                    decoration: const V2InputDecoration(
                      labelText: 'Date de constatation avec fuseau',
                    ),
                    validator: (v) =>
                        DateTime.tryParse(v ?? '') == null ||
                            !RegExp(
                              r'(Z|[+-][0-9]{2}:[0-9]{2})$',
                            ).hasMatch(v ?? '')
                        ? 'Date avec fuseau requise'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: c('reason'),
                    enabled: !busy && !uncertain,
                    maxLength: 500,
                    decoration: const V2InputDecoration(
                      labelText: 'Motif / justification obligatoire',
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Justification requise'
                        : null,
                  ),
                  TextFormField(
                    controller: c('note'),
                    enabled: !busy && !uncertain,
                    maxLength: 1000,
                    decoration: const V2InputDecoration(
                      labelText: 'Observations',
                    ),
                  ),
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
            style: TextButton.styleFrom(foregroundColor: V2Colors.navy),
            onPressed: busy || uncertain
                ? null
                : () => Navigator.pop(context, false),
            child: const Text('Annuler'),
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
