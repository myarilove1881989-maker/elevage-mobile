import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/v2_components.dart';
import 'husbandry_common.dart';

class ReproductionScreen extends StatefulWidget {
  const ReproductionScreen({
    super.key,
    required this.api,
    required this.lot,
    required this.species,
  });
  final ApiService api;
  final Map<String, dynamic> lot, species;
  @override
  State<ReproductionScreen> createState() => _ReproductionScreenState();
}

class _ReproductionScreenState extends State<ReproductionScreen> {
  late final service = HusbandryService(widget.api);
  List<Map<String, dynamic>> cycles = [],
      events = [],
      identities = [],
      births = [];
  String? error, identity, filterIdentity;
  bool loading = true;
  int tab = 0, generation = 0;
  DateTimeRange period = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 365)),
    end: DateTime.now(),
  );
  String eventName(String kind) =>
      {
        'MATING': 'Saillie / Insémination',
        'GESTATION': widget.species['family'] == 'CATTLE'
            ? 'Diagnostic de gestation'
            : 'Contrôle de gestation',
        'NEST': 'Préparation du nid',
        'BIRTH': widget.species['family'] == 'CATTLE' ? 'Vêlage' : 'Mise bas',
        'WEAN': 'Sevrage',
        'CLOSE': 'Clôture',
      }[kind] ??
      kind;
  @override
  void initState() {
    super.initState();
    identity = ApiService.sessionIdentity;
    widget.api.sessionChanges?.addListener(sessionChanged);
    load();
  }

  void sessionChanged() {
    if (identity != ApiService.sessionIdentity) {
      generation++;
      if (mounted) {
        setState(() {
          cycles = [];
          events = [];
          identities = [];
          births = [];
          error = 'Session terminée.';
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    widget.api.sessionChanges?.removeListener(sessionChanged);
    super.dispose();
  }

  Future<void> load() async {
    final ticket = ++generation, captured = ApiService.sessionIdentity;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final cs = await service.list(
        'reproduction/cycles/?lot=${widget.lot['id']}${filterIdentity == null ? '' : '&identity=$filterIdentity'}',
      );
      final es = await service.list(
        'reproduction/events/?lot=${widget.lot['id']}&from=${hDay(period.start)}&to=${hDay(period.end)}',
      );
      final ids = await service.list(
        'reproduction/identities/?species=${widget.species['id']}',
      );
      final detail = await widget.api.get('/lots/${widget.lot['id']}/');
      if (!mounted ||
          ticket != generation ||
          captured != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        cycles = cs;
        events = es;
        identities = ids;
        births = (detail['naissances_issues'] as List? ?? [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        loading = false;
      });
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          loading = false;
          cycles = [];
          events = [];
          births = [];
          error = hError(e);
        });
      }
    }
  }

  Future<void> createCycle() async {
    final name = TextEditingController(text: 'Cycle ${hDate(DateTime.now())}'),
        female = TextEditingController(),
        count = TextEditingController(text: '1');
    String mode = 'INDIVIDUAL';
    String? existing, failure;
    DateTime start = DateTime.now(), expected = DateTime.now();
    bool hasExpected = false, busy = false;
    final op = service.command({}), identityOp = service.command({});
    final route = DialogRoute<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => HDialog(
          title: 'Nouveau cycle',
          busy: busy,
          error: failure,
          children: [
            HField('Nom du cycle ou du groupe', name),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const V2InputDecoration(labelText: 'Mode'),
              items: const [
                DropdownMenuItem(
                  value: 'INDIVIDUAL',
                  child: Text('Individuel'),
                ),
                DropdownMenuItem(value: 'COLLECTIVE', child: Text('Collectif')),
              ],
              onChanged: busy ? null : (v) => update(() => mode = v!),
            ),
            const SizedBox(height: 18),
            if (mode == 'INDIVIDUAL') ...[
              if (identities.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: existing,
                  decoration: const V2InputDecoration(
                    labelText: 'Femelle identifiée',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Nouvel identifiant'),
                    ),
                    ...identities.map(
                      (i) => DropdownMenuItem<String>(
                        value: '${i['id']}',
                        child: Text(
                          '${i['label']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: busy ? null : (v) => update(() => existing = v),
                ),
                const SizedBox(height: 18),
              ],
              if (existing == null) HField('Identifiant de la femelle', female),
            ] else
              HField('Nombre de femelles', count, numeric: true),
            HDateField(
              label: 'Début du cycle',
              value: start,
              onChanged: (v) => update(() => start = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date prévue (facultative)'),
              value: hasExpected,
              onChanged: busy ? null : (v) => update(() => hasExpected = v!),
            ),
            if (hasExpected)
              HDateField(
                label: 'Date prévue',
                value: expected,
                onChanged: (v) => update(() => expected = v),
              ),
          ],
          onSave: () async {
            if (name.text.trim().isEmpty ||
                (mode == 'INDIVIDUAL' &&
                    existing == null &&
                    female.text.trim().isEmpty)) {
              update(() => failure = 'Renseignez le cycle et son identifiant.');
              return;
            }
            final n = mode == 'INDIVIDUAL'
                ? 1
                : int.tryParse(count.text.trim());
            if (n == null || n < 1) {
              update(() => failure = 'Indiquez un nombre entier de femelles.');
              return;
            }
            update(() {
              busy = true;
              failure = null;
            });
            try {
              String? selected = existing;
              if (mode == 'INDIVIDUAL' && selected == null) {
                final i = await service.send('reproduction/identities/', {
                  ...identityOp,
                  'species': widget.species['id'],
                  'label': female.text.trim(),
                });
                selected = '${i['id']}';
              }
              await service.send('reproduction/cycles/', {
                ...op,
                'lot': widget.lot['id'],
                'name': name.text.trim(),
                'mode': mode,
                'female_count': n,
                'identity': mode == 'INDIVIDUAL' ? selected : null,
                'started_on': hDay(start),
                'expected_on': hasExpected ? hDay(expected) : null,
              });
              if (dialog.mounted) Navigator.pop(dialog);
            } catch (e) {
              if (dialog.mounted) update(() => failure = hError(e));
            } finally {
              if (dialog.mounted) update(() => busy = false);
            }
          },
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    name.dispose();
    female.dispose();
    count.dispose();
    if (mounted) await load();
  }

  Future<void> addEvent(Map<String, dynamic> cycle) async {
    String kind = 'MATING',
        method = 'NATURAL',
        result = 'UNDETERMINED',
        productionType = 'CHAIR';
    String? failure;
    int? existingBirth;
    DateTime occurred = DateTime.now();
    bool busy = false;
    final op = service.command({});
    final fields = <String, TextEditingController>{};
    TextEditingController c(String key, {String text = ''}) =>
        fields.putIfAbsent(key, () => TextEditingController(text: text));
    final kinds = [
      'MATING',
      'GESTATION',
      if (widget.species['family'] == 'RABBIT') 'NEST',
      'BIRTH',
      'WEAN',
      'CLOSE',
    ];
    final route = DialogRoute<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => HDialog(
          title: 'Ajouter un événement',
          busy: busy,
          error: failure,
          children: [
            Text(
              '${cycle['name']}',
              style: Theme.of(dialog).textTheme.titleMedium,
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              key: ValueKey('event-$kind'),
              isExpanded: true,
              initialValue: kind,
              decoration: const V2InputDecoration(labelText: 'Événement'),
              items: kinds
                  .map(
                    (k) => DropdownMenuItem(
                      value: k,
                      child: Text(
                        eventName(k),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => update(() => kind = v!),
            ),
            const SizedBox(height: 18),
            HDateField(
              label: 'Date',
              value: occurred,
              onChanged: (v) => update(() => occurred = v),
            ),
            if (kind == 'MATING') ...[
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const V2InputDecoration(labelText: 'Mode'),
                items: const [
                  DropdownMenuItem(value: 'NATURAL', child: Text('Naturel')),
                  DropdownMenuItem(
                    value: 'ARTIFICIAL',
                    child: Text('Artificiel'),
                  ),
                ],
                onChanged: busy ? null : (v) => update(() => method = v!),
              ),
              const SizedBox(height: 18),
              HField(
                widget.species['family'] == 'RABBIT'
                    ? 'Mâle (facultatif)'
                    : widget.species['family'] == 'CATTLE'
                    ? 'Taureau / semence (facultatif)'
                    : 'Verrat / semence (facultatif)',
                c('male'),
              ),
            ],
            if (kind == 'GESTATION') ...[
              DropdownButtonFormField<String>(
                initialValue: result,
                decoration: const V2InputDecoration(labelText: 'Résultat'),
                items: const [
                  DropdownMenuItem(value: 'POSITIVE', child: Text('Positif')),
                  DropdownMenuItem(value: 'NEGATIVE', child: Text('Négatif')),
                  DropdownMenuItem(
                    value: 'UNDETERMINED',
                    child: Text('Indéterminé'),
                  ),
                ],
                onChanged: busy ? null : (v) => update(() => result = v!),
              ),
              const SizedBox(height: 18),
              if (widget.species['family'] == 'RABBIT')
                HField('Méthode (facultative)', c('control')),
            ],
            if (kind == 'NEST') HField('État de préparation', c('nest')),
            if (kind == 'BIRTH') ...[
              if (births.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey(existingBirth),
                  isExpanded: true,
                  initialValue: existingBirth,
                  decoration: const V2InputDecoration(
                    labelText: 'Naissance déjà enregistrée',
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Nouvelle naissance'),
                    ),
                    ...births.map(
                      (b) => DropdownMenuItem<int>(
                        value: b['id'] as int,
                        child: Text(
                          '${hDate(b['date'])} · ${b['nouveau_lot_nom']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => update(() {
                          existingBirth = v;
                          if (v != null) {
                            final b = births.firstWhere((b) => b['id'] == v);
                            c('alive').text = '${b['nes_vivants']}';
                            c('still').text = '${b['mort_nes']}';
                            occurred = DateTime.parse('${b['date']}');
                          }
                        }),
                ),
                const SizedBox(height: 18),
              ],
              if (cycle['mode'] == 'COLLECTIVE')
                HField(
                  widget.species['family'] == 'CATTLE'
                      ? 'Nombre de vêlages'
                      : 'Nombre de portées',
                  c('litters', text: '1'),
                  numeric: true,
                ),
              HField(
                'Nés vivants',
                c('alive', text: '0'),
                numeric: true,
                onChanged: (_) => update(() {}),
              ),
              HField('Mort-nés', c('still', text: '0'), numeric: true),
              if (existingBirth == null &&
                  (int.tryParse(c('alive').text) ?? 0) > 0) ...[
                HField('Lot des nouveau-nés (si vivants)', c('newLot')),
                DropdownButtonFormField<String>(
                  initialValue: productionType,
                  decoration: const V2InputDecoration(
                    labelText: 'Production du nouveau lot',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'CHAIR', child: Text('Chair')),
                    DropdownMenuItem(
                      value: 'REPRODUCTION',
                      child: Text('Reproduction'),
                    ),
                    DropdownMenuItem(value: 'AUTRE', child: Text('Autre')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => update(() => productionType = v!),
                ),
                const SizedBox(height: 18),
              ],
            ],
            if (kind == 'WEAN')
              HField('Nombre sevré', c('wean', text: '0'), numeric: true),
            if (kind == 'CLOSE') HField('Motif de clôture', c('reason')),
            HField('Observations (facultatives)', c('note'), lines: 2),
          ],
          onSave: () async {
            final data = <String, dynamic>{};
            int? n(String key) => int.tryParse(c(key).text.trim());
            if (kind == 'MATING') {
              data.addAll({
                'method': method,
                'male_origin': c('male').text.trim(),
              });
            }
            if (kind == 'GESTATION') {
              data.addAll({
                'result': result,
                if (widget.species['family'] == 'RABBIT')
                  'method': c('control').text.trim(),
              });
            }
            if (kind == 'NEST') data['state'] = c('nest').text.trim();
            if (kind == 'BIRTH') {
              if (n('alive') == null ||
                  n('still') == null ||
                  (cycle['mode'] == 'COLLECTIVE' && n('litters') == null)) {
                update(() => failure = 'Renseignez des effectifs entiers.');
                return;
              }
              data.addAll({
                'born_alive': n('alive'),
                'stillborn': n('still'),
                if (cycle['mode'] == 'COLLECTIVE') 'litters': n('litters'),
              });
              if (existingBirth != null) {
                data['existing_movement'] = existingBirth;
              } else if (n('alive')! > 0) {
                data.addAll({
                  'new_lot_name': c('newLot').text.trim(),
                  'production_type': productionType,
                });
              }
            }
            if (kind == 'WEAN') {
              if (n('wean') == null) {
                update(() => failure = 'Renseignez un nombre entier.');
                return;
              }
              data['count'] = n('wean');
            }
            if (kind == 'CLOSE') data['reason'] = c('reason').text.trim();
            update(() {
              busy = true;
              failure = null;
            });
            try {
              await service.send('reproduction/events/', {
                ...op,
                'cycle': cycle['id'],
                'expected_version': cycle['version'],
                'kind': kind,
                'occurred_on': hDay(occurred),
                'data': data,
                'note': c('note').text.trim(),
              });
              if (dialog.mounted) Navigator.pop(dialog);
            } catch (e) {
              if (dialog.mounted) update(() => failure = hError(e));
            } finally {
              if (dialog.mounted) update(() => busy = false);
            }
          },
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    for (final field in fields.values) {
      field.dispose();
    }
    if (mounted) await load();
  }

  Widget cycleCard(Map<String, dynamic> c) {
    final totals = c['totals'] as Map;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${c['name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${c['mode'] == 'INDIVIDUAL' ? c['identity_label'] : '${c['female_count']} femelles'} · ${hDate(c['started_on'])}',
            ),
            if (c['expected_on'] != null)
              Text('Prévision : ${hDate(c['expected_on'])}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Vivants : ${totals['born_alive']}')),
                Chip(label: Text('Mort-nés : ${totals['stillborn']}')),
                Chip(label: Text('Sevrés : ${totals['weaned']}')),
                Chip(
                  label: Text(
                    'Mortalités avant sevrage : ${totals['preweaning_mortality'] ?? '—'}',
                  ),
                ),
              ],
            ),
            if (c['status'] == 'OPEN') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => addEvent(c),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un événement'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String eventDetails(Map<String, dynamic> e) {
    final d = e['data'] as Map;
    switch (e['kind']) {
      case 'MATING':
        return '${d['method'] == 'ARTIFICIAL' ? 'Artificiel' : 'Naturel'}${'${d['male_origin'] ?? ''}'.isEmpty ? '' : ' · ${d['male_origin']}'}';
      case 'GESTATION':
        return {
              'POSITIVE': 'Positif',
              'NEGATIVE': 'Négatif',
              'UNDETERMINED': 'Indéterminé',
            }[d['result']] ??
            '';
      case 'NEST':
        return '${d['state']}';
      case 'BIRTH':
        return '${d['born_alive']} vivants · ${d['stillborn']} mort-nés${d['litters'] == null ? '' : ' · ${d['litters']} portées'}';
      case 'WEAN':
        return '${d['count']} sevrés';
      case 'CLOSE':
        return '${d['reason']}';
      default:
        return '';
    }
  }

  Widget history() {
    final visibleCycles = cycles.map((c) => c['id']).toSet();
    final list = events
        .where(
          (e) => filterIdentity == null || visibleCycles.contains(e['cycle']),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final p = await showDateRangePicker(
                context: context,
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
                initialDateRange: period,
              );
              if (p != null) {
                setState(() => period = p);
                await load();
              }
            },
            icon: const Icon(Icons.date_range_outlined),
            label: Text('${hDate(period.start)} – ${hDate(period.end)}'),
          ),
        ),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Aucun événement.'),
          ),
        for (final e in list)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${hDate(e['occurred_on'])} · ${eventName('${e['kind']}')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(eventDetails(e)),
                  if ('${e['note']}'.isNotEmpty) Text('${e['note']}'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = cycles
        .where((c) => c['status'] == (tab == 2 ? 'CLOSED' : 'OPEN'))
        .toList();
    return V2Scaffold(
      appBar: V2AppBar(
        title: const Text('Suivi de reproduction'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: HSection(
          title: '${widget.species['name']} · ${widget.lot['nom']}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in [
                    'En cours',
                    'Historique',
                    'Cycles terminés',
                  ].asMap().entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: tab == e.key,
                      onSelected: (_) => setState(() => tab = e.key),
                    ),
                  FilledButton.icon(
                    onPressed: loading ? null : createCycle,
                    icon: const Icon(Icons.add),
                    label: const Text('Nouveau cycle'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (identities.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: filterIdentity,
                  decoration: const V2InputDecoration(
                    labelText: 'Reproductrice',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Toutes'),
                    ),
                    ...identities.map(
                      (i) => DropdownMenuItem<String>(
                        value: '${i['id']}',
                        child: Text(
                          '${i['label']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => filterIdentity = v);
                    load();
                  },
                ),
                const SizedBox(height: 20),
              ],
              HError(error),
              if (loading)
                const Center(child: CircularProgressIndicator())
              else if (tab == 1)
                history()
              else if (list.isEmpty)
                const Text('Aucun cycle.')
              else
                ...list.map(cycleCard),
            ],
          ),
        ),
      ),
    );
  }
}
