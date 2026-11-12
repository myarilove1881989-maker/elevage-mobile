import 'package:flutter/material.dart';
import '../widgets/v2_components.dart';
import '../theme/design_system_v2.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';

String observationDecimal(String value) => value.trim().replaceAll(',', '.');
bool validObservationDecimal(String value, {bool positive = false}) {
  final text = observationDecimal(value);
  if (!RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$').hasMatch(text)) return false;
  if (!positive) return true;
  return !text.startsWith('-') && RegExp(r'[1-9]').hasMatch(text);
}

/// Online observations never enter the device outbox.
class ObservationPanel extends StatefulWidget {
  const ObservationPanel({
    super.key,
    required this.service,
    required this.kind,
    required this.rights,
    required this.installations,
    required this.cohorts,
  });
  final AquaticService service;
  final String kind;
  final List<String> rights;
  final List<Map<String, dynamic>> installations, cohorts;
  @override
  State<ObservationPanel> createState() => _ObservationPanelState();
}

class _ObservationPanelState extends State<ObservationPanel> {
  List<Map<String, dynamic>> rows = [];
  bool busy = true;
  String? error, target;
  int generation = 0;
  String get route => widget.kind == 'WEIGHT'
      ? 'weights/'
      : widget.kind == 'WATER'
      ? 'water-readings/'
      : 'observation-rules/';
  String get right => widget.kind == 'WEIGHT'
      ? 'aquatic.weights.create'
      : widget.kind == 'WATER'
      ? 'aquatic.water.create'
      : 'aquatic.water.rules.manage';
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

  Future<void> load() async {
    final epoch = ++generation, identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
      rows = [];
    });
    try {
      final data = await widget.service.list(route);
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        rows = data;
        busy = false;
      });
    } catch (_) {
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        rows = [];
        busy = false;
        error =
            'Historique indisponible. Vérifiez votre connexion et vos droits.';
      });
    }
  }

  String name(dynamic id) =>
      [
        ...widget.installations,
        ...widget.cohorts,
      ].where((r) => r['id'] == id).map((r) => '${r['name']}').firstOrNull ??
      '$id';
  List<Map<String, dynamic>> get filtered => target == null
      ? rows
      : rows
            .where((r) => r['cohort'] == target || r['installation'] == target)
            .toList();
  Future<void> add() async {
    final identity = ApiService.sessionIdentity;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ObservationEditor(
        service: widget.service,
        kind: widget.kind,
        installations: widget.installations,
        cohorts: widget.cohorts,
      ),
    );
    if (changed == true && mounted && identity == ApiService.sessionIdentity) {
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.kind == 'WEIGHT'
            ? 'Pesées et croissance'
            : widget.kind == 'WATER'
            ? 'Qualité de l’eau'
            : 'Règles et fraîcheur',
        style: Theme.of(context).textTheme.titleLarge,
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
            child: const Text('Actualiser'),
          ),
          if (widget.rights.contains(right))
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: V2Colors.navy,
                foregroundColor: Colors.white,
              ),
              onPressed: busy || error != null ? null : add,
              child: const Text('Enregistrer'),
            ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      if (widget.kind != 'RULE') ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: target,
          decoration: const V2InputDecoration(
            labelText: 'Historique d’une cohorte ou d’un bassin',
          ),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Tous — graphique séparé par cible'),
            ),
            ...[...widget.cohorts, ...widget.installations].map(
              (r) => DropdownMenuItem(
                value: '${r['id']}',
                child: Text('${r['name']}'),
              ),
            ),
          ],
          onChanged: (v) => setState(() => target = v),
        ),
        if (widget.kind == 'WEIGHT' &&
            target != null &&
            filtered.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Évolution du poids moyen (g) · cible sélectionnée uniquement',
          ),
          Semantics(
            label: 'Courbe chronologique du poids moyen en grammes',
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: CustomPaint(painter: WeightEvolutionPainter(filtered)),
            ),
          ),
        ],
      ],
      if (!busy && error == null && filtered.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aucun enregistrement.'),
        ),
      for (final row in filtered)
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: V2Colors.navy),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${name(row['cohort'] ?? row['installation'] ?? row['system_code'] ?? row['scope'])} · ${row['occurred_at'] ?? row['valid_from']}',
                ),
                if (widget.kind == 'WEIGHT') ...[
                  Text('Poids moyen : ${row['result']['mean_g']['decimal']} g'),
                  Text(
                    'Biomasse estimée : ${row['result']['biomass_kg']?['decimal'] ?? 'Indisponible — effectif non rapproché'}${row['result']['biomass_kg'] == null ? '' : ' kg'}',
                  ),
                  Text(
                    'Effectif de référence : ${row['result']['count_reference']['gross_count']} · ${row['result']['count_reference']['quality']}',
                  ),
                  Text(
                    'Date d’effectif : ${row['result']['count_reference']['at']} · Source : journal d’effectifs',
                  ),
                  Text(
                    'Âge : ${((row['freshness']['age_seconds'] as num) / 86400).toStringAsFixed(1)} jours · ${row['freshness']['status'] == 'UNCONFIGURED' ? 'fraîcheur non configurée' : row['freshness']['status']}',
                  ),
                  if (row['result']['biomass_kg'] == null)
                    Text(
                      'Estimation sur le brut : ${row['result']['gross_biomass_estimate_kg']['decimal']} kg — pertes non rapprochées, aucun vivant exact déduit.',
                    ),
                  const Text(
                    'Estimation issue de l’échantillon. Une pesée de bassin ne modifie aucun poids de cohorte.',
                  ),
                ] else if (widget.kind == 'WATER') ...[
                  Text(
                    'Température : ${row['temperature_c'] ?? 'Non renseignée'} °C · pH : ${row['ph'] ?? 'Non renseigné'} · O₂ : ${row['oxygen_mg_l'] ?? 'Non renseigné'} mg/L',
                  ),
                  for (final e in row['result']['evaluations'] as List)
                    Text(
                      '${e['parameter']} · ${e['cohort'] == null ? 'Installation' : name(e['cohort'])} : ${e['status']}${e['rule'] == null ? ' — aucun seuil pertinent' : ' · règle ${e['rule']['scope']} v${e['rule']['version']}'}',
                    ),
                  if ((row['result']['incompatible_population_thresholds']
                          as List)
                      .isNotEmpty)
                    const Text(
                      'Seuils incompatibles entre populations — évaluations individuelles conservées.',
                    ),
                  if (row['result']['has_alert'] == true)
                    const Text(
                      'Alerte : seuil configuré dépassé.',
                      style: TextStyle(color: Colors.red),
                    ),
                ] else ...[
                  Text(
                    '${row['parameter']} · ${row['scope']} · version ${row['version']}',
                  ),
                  Text(
                    'Borne basse : ${row['lower'] ?? 'Non définie'} · haute : ${row['upper'] ?? 'Non définie'} ${row['unit']}',
                  ),
                  Text('Fin exclusive : ${row['valid_to'] ?? 'Sans fin'}'),
                ],
                if (row['note'] != null && row['note'] != '')
                  Text('${row['note']}'),
              ],
            ),
          ),
        ),
    ],
  );
}

/// Float conversion is for painting only; canonical calculations stay on the server.
class WeightEvolutionPainter extends CustomPainter {
  WeightEvolutionPainter(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  void paint(Canvas canvas, Size size) {
    final ordered = [...rows]
      ..sort((a, b) => '${a['occurred_at']}'.compareTo('${b['occurred_at']}'));
    final values = ordered
        .map((r) => double.parse('${r['result']['mean_g']['decimal']}'))
        .toList();
    if (values.isEmpty) return;
    final times = ordered
        .map(
          (r) => DateTime.parse(
            r['occurred_at'] as String,
          ).millisecondsSinceEpoch.toDouble(),
        )
        .toList();
    final max = values.reduce((a, b) => a > b ? a : b);
    final span = times.last - times.first;
    final paint = Paint()
      ..color = V2Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x =
          12 +
          (span == 0 ? 0 : (times[i] - times.first) / span) * (size.width - 24);
      final y =
          size.height -
          16 -
          (max == 0 ? 0 : values[i] / max) * (size.height - 32);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = V2Colors.green);
    }
    canvas.drawPath(path, paint);
    final axis = Paint()
      ..color = V2Colors.navy
      ..strokeWidth = 1;
    canvas.drawLine(Offset(12, 8), Offset(12, size.height - 16), axis);
    canvas.drawLine(
      Offset(12, size.height - 16),
      Offset(size.width - 8, size.height - 16),
      axis,
    );
    final label = TextPainter(
      text: TextSpan(
        text: '0 - ${max.toStringAsFixed(2)} g',
        style: const TextStyle(
          color: V2Colors.navy,
          fontSize: 12,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(18, 0));
    final dates = TextPainter(
      text: TextSpan(
        text:
            '${ordered.first['occurred_at'].toString().substring(0, 10)} au ${ordered.last['occurred_at'].toString().substring(0, 10)}',
        style: const TextStyle(
          color: V2Colors.navy,
          fontSize: 11,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 24);
    dates.paint(canvas, Offset(18, size.height - 14));
  }

  @override
  bool shouldRepaint(covariant WeightEvolutionPainter oldDelegate) =>
      oldDelegate.rows != rows;
}

class ObservationEditor extends StatefulWidget {
  const ObservationEditor({
    super.key,
    required this.service,
    required this.kind,
    required this.installations,
    required this.cohorts,
  });
  final AquaticService service;
  final String kind;
  final List<Map<String, dynamic>> installations, cohorts;
  @override
  State<ObservationEditor> createState() => _ObservationEditorState();
}

class _ObservationEditorState extends State<ObservationEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String targetKind = 'cohort',
      method = 'SAMPLE',
      scope = 'INSTALLATION',
      parameter = 'oxygen_mg_l';
  String? cohort, installation, stage, supersedes;
  List<Map<String, dynamic>> stages = [], rules = [];
  bool busy = false, uncertain = false;
  String? error;
  Map<String, dynamic>? pending;
  String? pendingRoute;
  TextEditingController c(String key, [String initial = '']) =>
      fields.putIfAbsent(key, () => TextEditingController(text: initial));
  @override
  void initState() {
    super.initState();
    cohort = widget.cohorts.firstOrNull?['id'] as String?;
    installation = widget.installations.firstOrNull?['id'] as String?;
    c('at', DateTime.now().toUtc().toIso8601String());
    c('count_at', c('at').text);
    if (widget.kind == 'RULE') loadStages();
  }

  Future<void> loadStages() async {
    final identity = ApiService.sessionIdentity;
    try {
      final data = await widget.service.list('stages/');
      final saved = await widget.service.list('observation-rules/');
      if (mounted && identity == ApiService.sessionIdentity) {
        setState(() {
          stages = data;
          rules = saved;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Stades indisponibles.');
    }
  }

  @override
  void dispose() {
    for (final v in fields.values) {
      v.dispose();
    }
    super.dispose();
  }

  Widget number(
    String key,
    String label, {
    bool positive = false,
    bool optional = false,
    bool integer = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c(key),
      enabled: !busy && !uncertain,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: V2InputDecoration(labelText: label),
      validator: (v) {
        if (optional && (v ?? '').trim().isEmpty) return null;
        if (integer) {
          return RegExp(r'^[1-9][0-9]*$').hasMatch(v ?? '')
              ? null
              : 'Entier strictement positif requis';
        }
        return validObservationDecimal(v ?? '', positive: positive)
            ? null
            : 'Valeur décimale valide requise';
      },
    ),
  );
  Widget dateField(String key, String label, {bool optional = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c(key),
          enabled: !busy && !uncertain,
          decoration: V2InputDecoration(
            labelText: label,
            hintText: '2026-11-12T10:00:00+01:00',
          ),
          validator: (v) {
            if (optional && (v ?? '').trim().isEmpty) return null;
            final text = v ?? '';
            if (DateTime.tryParse(text) == null ||
                !RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(text)) {
              return 'Date avec fuseau requise';
            }
            return null;
          },
        ),
      );
  Widget choose(
    String label,
    String? value,
    List<Map<String, dynamic>> rows,
    ValueChanged<String?> onChange,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      isExpanded: true,
      key: ValueKey('$label:$value'),
      initialValue: value,
      decoration: V2InputDecoration(labelText: label),
      items: rows
          .map(
            (r) => DropdownMenuItem(
              value: '${r['id']}',
              child: Text('${r['name']}', overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: busy || uncertain ? null : onChange,
      validator: (v) => v == null ? 'Sélection requise' : null,
    ),
  );
  Future<void> save() async {
    if (!uncertain) {
      if (!form.currentState!.validate()) return;
      final d = <String, dynamic>{};
      final at = DateTime.parse(c('at').text).toUtc().toIso8601String();
      if (widget.kind == 'WEIGHT') {
        d[targetKind] = targetKind == 'cohort' ? cohort : installation;
        d['occurred_at'] = at;
        d['count_reference_at'] = DateTime.parse(
          c('count_at').text,
        ).toUtc().toIso8601String();
        if (method == 'SAMPLE') {
          d['sample_count'] = int.parse(c('sample_count').text);
          d['mass_kg'] = observationDecimal(c('mass_kg').text);
        } else {
          d['direct_mean_g'] = observationDecimal(c('direct_mean_g').text);
        }
      } else if (widget.kind == 'WATER') {
        d['installation'] = installation;
        d['occurred_at'] = at;
        for (final key in ['temperature_c', 'ph', 'oxygen_mg_l']) {
          if (c(key).text.trim().isNotEmpty) {
            d[key] = observationDecimal(c(key).text);
          }
        }
        if (d.length == 2) {
          setState(() => error = 'Renseignez au moins une mesure d’eau.');
          return;
        }
      } else {
        d['parameter'] = parameter;
        d['scope'] = scope;
        d['valid_from'] = at;
        if (supersedes != null) d['supersedes'] = supersedes;
        if (c('end').text.isNotEmpty) {
          d['valid_to'] = DateTime.parse(
            c('end').text,
          ).toUtc().toIso8601String();
        }
        if (scope == 'INSTALLATION') {
          d['installation'] = installation;
        } else if (scope == 'SYSTEM') {
          d['system_code'] = c('system_code').text.trim();
        } else {
          final row = stages.where((r) => r['id'] == stage).first;
          d['stage'] = stage;
          d['species'] = row['species'];
        }
        for (final key in ['lower', 'upper']) {
          if (c(key).text.trim().isNotEmpty) {
            d[key] = observationDecimal(c(key).text);
          }
        }
        if (!d.containsKey('lower') && !d.containsKey('upper')) {
          setState(() => error = 'Renseignez au moins une borne.');
          return;
        }
      }
      if (widget.kind != 'RULE') d['note'] = c('note').text;
      pending = widget.service.command(d);
      pendingRoute = widget.kind == 'WEIGHT'
          ? 'weights/'
          : widget.kind == 'WATER'
          ? 'water-readings/'
          : 'observation-rules/';
    }
    final identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.send(pendingRoute!, pending!);
      if (!mounted || identity != ApiService.sessionIdentity) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted || identity != ApiService.sessionIdentity) return;
      final ambiguous = e is! ApiHttpException || e.status >= 500;
      setState(() {
        busy = false;
        uncertain = ambiguous;
        error = ambiguous
            ? 'Réponse incertaine. Réessayez la même opération pour éviter un doublon.'
            : 'Enregistrement refusé : ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !uncertain,
    child: V2AlertDialog(
      title: Text(
        widget.kind == 'WEIGHT'
            ? 'Enregistrer une pesée'
            : widget.kind == 'WATER'
            ? 'Relevé d’eau partiel'
            : 'Configurer une règle',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.kind == 'WEIGHT') ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: targetKind,
                    decoration: const V2InputDecoration(labelText: 'Périmètre'),
                    items: const [
                      DropdownMenuItem(value: 'cohort', child: Text('Cohorte')),
                      DropdownMenuItem(
                        value: 'installation',
                        child: Text('Bassin'),
                      ),
                    ],
                    onChanged: busy || uncertain
                        ? null
                        : (v) => setState(() => targetKind = v!),
                  ),
                  const SizedBox(height: 12),
                  if (targetKind == 'cohort')
                    choose(
                      'Cohorte',
                      cohort,
                      widget.cohorts,
                      (v) => setState(() => cohort = v),
                    )
                  else
                    choose(
                      'Bassin',
                      installation,
                      widget.installations,
                      (v) => setState(() => installation = v),
                    ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: method,
                    decoration: const V2InputDecoration(labelText: 'Méthode'),
                    items: const [
                      DropdownMenuItem(
                        value: 'SAMPLE',
                        child: Text('Échantillon : n et masse'),
                      ),
                      DropdownMenuItem(
                        value: 'DIRECT_MEAN',
                        child: Text('Poids moyen direct'),
                      ),
                    ],
                    onChanged: busy || uncertain
                        ? null
                        : (v) => setState(() => method = v!),
                  ),
                  const SizedBox(height: 12),
                  if (method == 'SAMPLE') ...[
                    number(
                      'sample_count',
                      'Nombre de poissons échantillonnés (n)',
                      integer: true,
                    ),
                    number(
                      'mass_kg',
                      'Masse de l’échantillon (kg)',
                      positive: true,
                    ),
                  ] else
                    number(
                      'direct_mean_g',
                      'Poids moyen direct (g)',
                      positive: true,
                    ),
                  dateField('count_at', 'Date de référence de l’effectif'),
                  const Text(
                    'L’effectif sera calculé depuis le journal à cette date. Les pertes non rapprochées rendent la biomasse incertaine.',
                  ),
                ] else if (widget.kind == 'WATER') ...[
                  choose(
                    'Bassin',
                    installation,
                    widget.installations,
                    (v) => setState(() => installation = v),
                  ),
                  const Text(
                    'Au moins une valeur. Un champ vide reste inconnu ; zéro est une mesure.',
                  ),
                  number('temperature_c', 'Température (°C)', optional: true),
                  number('ph', 'pH (sans unité)', optional: true),
                  number(
                    'oxygen_mg_l',
                    'Oxygène dissous (mg/L)',
                    optional: true,
                  ),
                ] else ...[
                  const Text(
                    'Aucun seuil biologique par défaut. Une règle datée est conservée sans réécrire les anciennes évaluations.',
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: parameter,
                    decoration: const V2InputDecoration(
                      labelText: 'Paramètre et unité',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'temperature_c',
                        child: Text('Température (°C)'),
                      ),
                      DropdownMenuItem(value: 'ph', child: Text('pH')),
                      DropdownMenuItem(
                        value: 'oxygen_mg_l',
                        child: Text('O₂ (mg/L)'),
                      ),
                      DropdownMenuItem(
                        value: 'weight_age_days',
                        child: Text('Fraîcheur des pesées (jours)'),
                      ),
                    ],
                    onChanged: busy || uncertain
                        ? null
                        : (v) => setState(() => parameter = v!),
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: scope,
                    decoration: const V2InputDecoration(
                      labelText: 'Priorité de la règle',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'INSTALLATION',
                        child: Text('Installation (priorité 1)'),
                      ),
                      DropdownMenuItem(
                        value: 'SPECIES_STAGE',
                        child: Text('Espèce et stade (priorité 2)'),
                      ),
                      DropdownMenuItem(
                        value: 'SYSTEM',
                        child: Text('Système (priorité 3)'),
                      ),
                    ],
                    onChanged: busy || uncertain
                        ? null
                        : (v) => setState(() => scope = v!),
                  ),
                  const SizedBox(height: 12),
                  if (scope == 'INSTALLATION')
                    choose(
                      'Bassin',
                      installation,
                      widget.installations,
                      (v) => setState(() => installation = v),
                    )
                  else if (scope == 'SPECIES_STAGE')
                    choose(
                      'Espèce / stade',
                      stage,
                      stages
                          .map(
                            (s) => {
                              ...s,
                              'name': 'Espèce ${s['species']} · ${s['name']}',
                            },
                          )
                          .toList(),
                      (v) => setState(() => stage = v),
                    )
                  else
                    TextFormField(
                      controller: c('system_code'),
                      enabled: !busy && !uncertain,
                      decoration: const V2InputDecoration(
                        labelText: 'Code du système',
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Code requis' : null,
                    ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: supersedes,
                    decoration: const V2InputDecoration(
                      labelText: 'Règle remplacée (facultative)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Nouvelle règle'),
                      ),
                      ...rules.map(
                        (r) => DropdownMenuItem(
                          value: r['id'] as String,
                          child: Text(
                            '${r['parameter']} · ${r['scope']} · v${r['version']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: busy || uncertain
                        ? null
                        : (v) => setState(() => supersedes = v),
                  ),
                  number('lower', 'Borne basse (facultative)', optional: true),
                  number('upper', 'Borne haute (facultative)', optional: true),
                  dateField(
                    'end',
                    'Fin de validité exclusive (facultative)',
                    optional: true,
                  ),
                ],
                dateField(
                  'at',
                  widget.kind == 'RULE'
                      ? 'Début de validité'
                      : 'Date de la mesure',
                ),
                if (widget.kind != 'RULE')
                  TextFormField(
                    controller: c('note'),
                    enabled: !busy && !uncertain,
                    maxLength: 500,
                    decoration: const V2InputDecoration(
                      labelText: 'Note et incertitude de l’échantillon',
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
