import 'package:flutter/material.dart';
import '../widgets/v2_components.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';

class AquaticForm extends StatefulWidget {
  const AquaticForm({
    super.key,
    required this.service,
    required this.kind,
    required this.installations,
    required this.cohorts,
    required this.species,
    this.entity,
  });
  final AquaticService service;
  final String kind;
  final List<Map<String, dynamic>> installations, cohorts, species;
  final Map<String, dynamic>? entity;
  @override
  State<AquaticForm> createState() => _AquaticFormState();
}

class _AquaticFormState extends State<AquaticForm> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{},
      counts = <String, TextEditingController>{};
  late List<Map<String, dynamic>> installations, species;
  List<Map<String, dynamic>> stages = [];
  String? selectedSpecies, selectedStage, selectedCohort, source, destination;
  String type = 'BASSIN', status = 'ACTIVE', origin = 'PURCHASE', unit = '';
  bool busy = false, uncertain = false;
  String? error;
  int step = 0;
  DateTime at = DateTime.now();
  Map<String, dynamic>? pending;
  String? pendingPath;
  bool pendingPatch = false;
  void Function(Map<String, dynamic>)? pendingAfter;
  late final String entityId;
  String get kind => widget.kind;
  bool get wizard => kind == 'onboarding';
  TextEditingController c(String name, [String value = '']) =>
      fields.putIfAbsent(name, () => TextEditingController(text: value));
  @override
  void initState() {
    super.initState();
    installations = [...widget.installations];
    species = [...widget.species];
    entityId =
        widget.entity?['id'] as String? ??
        '${widget.service.command({})['operation_uuid']}';
    final row = widget.entity;
    if (row != null) {
      for (final key in [
        'name',
        'code',
        'capacity',
        'location',
        'system_code',
      ]) {
        c(key, row[key]?.toString() ?? '');
      }
      status = row['status'] as String? ?? 'ACTIVE';
      type = row['type'] as String? ?? 'BASSIN';
      unit = row['capacity_unit'] as String? ?? '';
      selectedSpecies = row['species']?.toString();
      selectedStage = row['stage'] as String?;
    }
    selectedSpecies ??= species.firstOrNull?['species']?.toString();
    if (widget.cohorts.isNotEmpty) {
      selectedCohort = widget.cohorts.first['id'] as String;
    }
    source = installations.firstOrNull?['id'] as String?;
    destination = installations.length > 1
        ? installations[1]['id'] as String
        : null;
    if (selectedSpecies != null) loadStages();
  }

  @override
  void dispose() {
    for (final controller in [...fields.values, ...counts.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> loadStages() async {
    final speciesId = selectedSpecies;
    try {
      final rows = await widget.service.list('stages/?species=$speciesId');
      if (mounted && speciesId == selectedSpecies) {
        setState(() => stages = rows);
      }
    } catch (_) {
      if (mounted) setState(() => stages = []);
    }
  }

  Widget text(
    String name,
    String label, {
    bool required = true,
    bool numeric = false,
    String? help,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: V2Field(
      child: TextFormField(
        key: ValueKey('aquatic-$name'),
        controller: c(name),
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: V2InputDecoration(
          labelText: label,
          helperText: help,
          prefixIcon: const Icon(Icons.edit_outlined),
        ),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return 'Champ nécessaire';
          }
          return null;
        },
      ),
    ),
  );
  Widget pick(
    String label,
    String? value,
    List<(String, String)> options,
    ValueChanged<String?> onChange,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: V2Field(
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label:$value'),
        initialValue: options.any((o) => o.$1 == value) ? value : null,
        isExpanded: true,
        decoration: V2InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.water),
        ),
        items: options
            .map(
              (o) => DropdownMenuItem(
                value: o.$1,
                child: Text(o.$2, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: busy ? null : onChange,
      ),
    ),
  );
  Widget date() => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month),
      label: Text(
        'Date et heure : ${at.toLocal().toString().substring(0, 16)}',
      ),
      onPressed: busy
          ? null
          : () async {
              final day = await showDatePicker(
                context: context,
                initialDate: at,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (day == null || !mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(at),
              );
              if (time != null && mounted) {
                setState(
                  () => at = DateTime(
                    day.year,
                    day.month,
                    day.day,
                    time.hour,
                    time.minute,
                  ),
                );
              }
            },
    ),
  );
  List<Widget> installationFields() => [
    text('name', 'Nom de l’installation'),
    text('code', 'Code'),
    pick('Type', type, [
      (forValue('BASSIN'), 'Bassin'),
      ('ETANG', 'Étang'),
      ('CAGE', 'Cage'),
      ('BAC', 'Bac'),
    ], (v) => setState(() => type = v!)),
    text('capacity', 'Capacité (facultative)', required: false, numeric: true),
    pick('Unité', unit, [
      ('', 'Non renseignée'),
      ('m3', 'm³'),
      ('L', 'Litres'),
      ('m2', 'm²'),
    ], (v) => setState(() => unit = v!)),
    text('location', 'Localisation interne', required: false),
    text('system_code', 'Système (facultatif)', required: false),
    if (widget.entity != null)
      pick('Statut', status, [
        ('ACTIVE', 'Actif'),
        ('INACTIVE', 'Inactif'),
      ], (v) => setState(() => status = v!)),
    const Text(
      'La désactivation conserve l’historique et exige une installation vide.',
    ),
  ];
  String forValue(String value) => value;
  List<Widget> speciesFields() => [
    if (species.isNotEmpty)
      pick(
        'Espèce aquatique',
        selectedSpecies,
        species.map((s) => ('${s['species']}', '${s['name']}')).toList(),
        (v) {
          setState(() {
            selectedSpecies = v;
            selectedStage = null;
          });
          loadStages();
        },
      ),
    text(
      'new_species',
      'Nouvelle espèce aquatique (facultatif)',
      required: false,
      help:
          'Crée une espèce dans votre exploitation, sans modifier les espèces terrestres.',
    ),
    if (!wizard)
      OutlinedButton(
        onPressed: busy ? null : createSpecies,
        child: const Text('Ajouter cette espèce au catalogue aquatique'),
      ),
    if (stages.isNotEmpty)
      pick('Stade (facultatif)', selectedStage, [
        ('', 'Non renseigné'),
        ...stages.map((s) => ('${s['id']}', '${s['name']}')),
      ], (v) => setState(() => selectedStage = v)),
    if (!wizard) ...[
      text('stage_name', 'Nouveau stade (facultatif)', required: false),
      OutlinedButton(
        onPressed: busy ? null : createStage,
        child: const Text('Ajouter un stade'),
      ),
    ],
  ];
  List<Widget> cohortFields() => [
    text('cohort_name', 'Nom de la cohorte'),
    text('cohort_code', 'Code de la cohorte'),
    pick('Origine', origin, [
      ('PURCHASE', 'Achat déclaré'),
      ('HATCH', 'Alevinage'),
      ('TRANSFER_IN', 'Origine externe'),
      ('OTHER', 'Autre'),
    ], (v) => setState(() => origin = v!)),
    date(),
    const Text('Déclarer une origine ne crée ni achat ni dépense.'),
  ];
  List<Widget> allocations() => [
    text('initial_count', 'Effectif initial (poissons)', numeric: true),
    const Text(
      'Répartissez cet effectif entre les installations. Le total doit correspondre exactement.',
    ),
    const SizedBox(height: 16),
    if (wizard) allocation(entityId, c('name').text),
    for (final installation in installations.where(
      (i) => i['status'] == 'ACTIVE',
    ))
      allocation('${installation['id']}', '${installation['name']}'),
    text('reason', 'Motif / provenance'),
  ];
  Widget allocation(String id, String name) {
    final ctrl = counts.putIfAbsent(id, () => TextEditingController());
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        key: ValueKey('allocation-$id'),
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: V2InputDecoration(
          labelText: 'Poissons · $name',
          prefixIcon: const Icon(Icons.pool),
        ),
      ),
    );
  }

  Future<void> createSpecies() async {
    final name = c('new_species').text.trim();
    if (name.isEmpty) return;
    await perform(
      'species/',
      widget.service.command({
        'id': widget.service.command({})['operation_uuid'],
        'name': name,
      }),
      after: (result) {
        species.add(result);
        selectedSpecies = '${result['species']}';
        c('new_species').clear();
      },
    );
  }

  Future<void> createStage() async {
    if (selectedSpecies == null || c('stage_name').text.trim().isEmpty) return;
    final name = c('stage_name').text.trim();
    await perform(
      'stages/',
      widget.service.command({
        'id': widget.service.command({})['operation_uuid'],
        'species': int.parse(selectedSpecies!),
        'name': name,
        'code': name,
      }),
      after: (result) {
        stages.add(result);
        selectedStage = '${result['id']}';
        c('stage_name').clear();
      },
    );
  }

  Future<void> perform(
    String path,
    Map<String, dynamic> body, {
    void Function(Map<String, dynamic>)? after,
    bool patch = false,
  }) async {
    setState(() {
      busy = true;
      error = null;
    });
    pending = body;
    pendingPath = path;
    pendingPatch = patch;
    pendingAfter = after;
    try {
      final result = patch
          ? await widget.service.patch(
              path,
              body,
              '"${widget.entity!['id']}:${widget.entity!['version']}"',
            )
          : await widget.service.send(path, body);
      if (!mounted) return;
      if (after != null) {
        setState(() {
          after(result);
          busy = false;
          uncertain = false;
          pending = null;
          pendingPath = null;
        });
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        uncertain =
            e is! ApiHttpException || e.status >= 500 || e.status == 408;
        error = uncertain
            ? 'Réponse interrompue : résultat à vérifier. Ne ressaisissez pas cette opération.'
            : e.toString();
        if (!uncertain) {
          pending = null;
          pendingPath = null;
        }
      });
    }
  }

  Future<void> verify() async {
    if (pending == null) return;
    setState(() => busy = true);
    try {
      final r = await widget.service.read(
        'commands/${pending!['operation_uuid']}/',
      );
      if (!mounted) return;
      if (r['status'] == 'APPLIED') {
        if (pendingAfter != null) {
          setState(() {
            pendingAfter!(Map<String, dynamic>.from(r['result'] as Map));
            pending = null;
            pendingAfter = null;
            pendingPath = null;
            uncertain = false;
            busy = false;
            error = null;
          });
        } else {
          Navigator.pop(context, true);
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Résultat non confirmé. Gardez cet écran ; une reprise doit conserver le même identifiant et les mêmes données.',
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> resume() async {
    final body = pending;
    final path = pendingPath;
    if (busy || body == null || path == null) return;
    await perform(path, body, after: pendingAfter, patch: pendingPatch);
  }

  Future<void> submit() async {
    if (!form.currentState!.validate() || busy || uncertain) return;
    if (wizard && step < 3) {
      setState(() => step++);
      return;
    }
    try {
      Map<String, dynamic> data;
      String path;
      bool patch = false;
      if (kind == 'installation') {
        data = {
          'name': c('name').text.trim(),
          'code': c('code').text.trim(),
          'type': type,
          'capacity': c('capacity').text.trim().isEmpty
              ? null
              : c('capacity').text.trim().replaceAll(',', '.'),
          'capacity_unit': unit,
          'location': c('location').text.trim(),
          'system_code': c('system_code').text.trim(),
          if (widget.entity != null) 'status': status,
        };
        path = 'installations/${widget.entity == null ? '' : '$entityId/'}';
        patch = widget.entity != null;
        if (!patch) data['id'] = entityId;
      } else if (kind == 'cohort_edit') {
        data = {
          'name': c('name', widget.entity!['name'] as String).text.trim(),
          'stage': selectedStage?.isEmpty == true ? null : selectedStage,
          'status': status,
        };
        path = 'cohorts/$entityId/';
        patch = true;
      } else if (kind == 'transfer') {
        final count = int.tryParse(c('count').text);
        if (count == null ||
            count <= 0 ||
            selectedCohort == null ||
            source == null ||
            destination == null ||
            source == destination) {
          throw StateError(
            'Choisissez une cohorte, deux installations différentes et un effectif entier positif.',
          );
        }
        final row = widget.cohorts.firstWhere((c) => c['id'] == selectedCohort);
        final ps = (row['positions'] as List).cast<Map>();
        final src = ps.where((p) => p['installation'] == source).firstOrNull;
        final dst = ps
            .where((p) => p['installation'] == destination)
            .firstOrNull;
        if (src == null) {
          throw StateError('Cette cohorte n’occupe pas l’installation source.');
        }
        data = {
          'cohort': selectedCohort,
          'source': source,
          'destination': destination,
          'count': count,
          'occurred_at': at.toUtc().toIso8601String(),
          'reason': c('reason').text.trim(),
          'expected_versions': {
            'cohort': row['version'],
            'source_position': src['version'],
            'destination_position': dst?['version'] ?? 0,
          },
        };
        path = 'transfers/';
      } else {
        final initial = int.tryParse(c('initial_count').text);
        final lines = <Map<String, dynamic>>[];
        for (final entry in counts.entries) {
          final raw = entry.value.text.trim();
          if (raw.isEmpty) continue;
          final count = int.tryParse(raw);
          if (count == null || count < 0) {
            throw StateError('Chaque affectation doit être un entier positif.');
          }
          if (count > 0) lines.add({'installation': entry.key, 'count': count});
        }
        if (initial == null ||
            initial <= 0 ||
            lines.fold<int>(0, (sum, a) => sum + (a['count'] as int)) !=
                initial) {
          throw StateError(
            'La somme des affectations doit égaler l’effectif initial.',
          );
        }
        data = {
          'id': wizard
              ? widget.service.command({})['operation_uuid']
              : entityId,
          'name': c('cohort_name').text.trim(),
          'code': c('cohort_code').text.trim(),
          'stage': selectedStage?.isEmpty == true ? null : selectedStage,
          'origin': {'type': origin, 'reference': null},
          'started_at': at.toUtc().toIso8601String(),
          'initial_count': initial,
          'allocations': lines,
          'reason': c('reason').text.trim(),
        };
        if (wizard) {
          final newName = c('new_species').text.trim();
          if (newName.isEmpty && selectedSpecies == null) {
            throw StateError('Choisissez ou nommez une espèce aquatique.');
          }
          data = {
            'installation': {
              'id': entityId,
              'name': c('name').text.trim(),
              'code': c('code').text.trim(),
              'type': type,
              'location': c('location').text.trim(),
              'system_code': c('system_code').text.trim(),
              'capacity': c('capacity').text.trim().isEmpty
                  ? null
                  : c('capacity').text.trim().replaceAll(',', '.'),
              'capacity_unit': unit,
            },
            'species': newName.isNotEmpty
                ? {
                    'id': widget.service.command({})['operation_uuid'],
                    'name': newName,
                  }
                : {'existing_species': int.parse(selectedSpecies!)},
            'cohort': data,
          };
          path = 'onboarding/';
        } else {
          if (selectedSpecies == null) {
            throw StateError('Choisissez une espèce aquatique.');
          }
          data['species'] = int.parse(selectedSpecies!);
          path = 'cohorts/';
        }
      }
      await perform(path, widget.service.command(data), patch: patch);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = wizard
        ? 'Premier démarrage · ${step + 1}/4'
        : {
            'installation': 'Installation piscicole',
            'cohort': 'Nouvelle cohorte',
            'cohort_edit': 'Modifier la cohorte',
            'transfer': 'Transférer des poissons',
          }[kind]!;
    return V2Scaffold(
      protectDraft: true,
      busy: busy,
      appBar: V2AppBar(title: Text(title)),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'En ligne uniquement. La validation finale est effectuée par le serveur.',
                    ),
                    const SizedBox(height: 24),
                    if (wizard) ...[
                      if (step == 0) ...installationFields(),
                      if (step == 1) ...speciesFields(),
                      if (step == 2) ...cohortFields(),
                      if (step == 3) ...allocations(),
                    ] else if (kind == 'installation')
                      ...installationFields()
                    else if (kind == 'cohort_edit') ...[
                      text('name', 'Nom de la cohorte'),
                      if (stages.isNotEmpty)
                        pick('Stade', selectedStage, [
                          ('', 'Non renseigné'),
                          ...stages.map((s) => ('${s['id']}', '${s['name']}')),
                        ], (v) => setState(() => selectedStage = v)),
                      pick('Statut', status, [
                        ('OPEN', 'En cours'),
                        ('CLOSED', 'Clôturée'),
                      ], (v) => setState(() => status = v!)),
                      const Text(
                        'La clôture exige un effectif nul et aucune perte en attente.',
                      ),
                    ] else if (kind == 'cohort')
                      ...speciesFields() + cohortFields() + allocations()
                    else ...[
                      pick(
                        'Cohorte',
                        selectedCohort,
                        widget.cohorts
                            .map((c) => ('${c['id']}', '${c['name']}'))
                            .toList(),
                        (v) => setState(() => selectedCohort = v),
                      ),
                      pick(
                        'Installation source',
                        source,
                        installations
                            .map((i) => ('${i['id']}', '${i['name']}'))
                            .toList(),
                        (v) => setState(() => source = v),
                      ),
                      pick(
                        'Installation destination',
                        destination,
                        installations
                            .map((i) => ('${i['id']}', '${i['name']}'))
                            .toList(),
                        (v) => setState(() => destination = v),
                      ),
                      text('count', 'Nombre à transférer', numeric: true),
                      date(),
                      text('reason', 'Motif'),
                      const Text(
                        'Le total reste identique. Une réserve de pertes en attente réduit la quantité transférable.',
                      ),
                    ],
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
                    if (busy) const LinearProgressIndicator(),
                    if (uncertain)
                      OutlinedButton(
                        onPressed: busy ? null : verify,
                        child: const Text('Vérifier le résultat'),
                      ),
                    if (uncertain)
                      OutlinedButton(
                        onPressed: busy ? null : resume,
                        child: const Text('Reprendre la même opération'),
                      ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (wizard && step > 0)
                          OutlinedButton(
                            onPressed: busy || uncertain
                                ? null
                                : () => setState(() => step--),
                            child: const Text('Précédent'),
                          ),
                        ElevatedButton(
                          onPressed: busy || uncertain ? null : submit,
                          child: Text(
                            wizard && step < 3 ? 'Continuer' : 'Confirmer',
                          ),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.maybePop(context),
                          child: const Text('Annuler'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
