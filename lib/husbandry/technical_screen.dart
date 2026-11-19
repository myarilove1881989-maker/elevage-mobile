import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/v2_components.dart';
import '../theme/design_system_v2.dart';
import 'husbandry_common.dart';

class TechnicalScreen extends StatefulWidget {
  const TechnicalScreen({
    super.key,
    required this.api,
    required this.lot,
    required this.species,
  });
  final ApiService api;
  final Map<String, dynamic> lot, species;
  @override
  State<TechnicalScreen> createState() => _TechnicalScreenState();
}

class _TechnicalScreenState extends State<TechnicalScreen> {
  late final service = HusbandryService(widget.api);
  List<Map<String, dynamic>> parameters = [], rules = [], rows = [];
  final fields = <String, TextEditingController>{};
  final booleans = <String, bool?>{};
  final note = TextEditingController();
  DateTime occurred = DateTime.now();
  DateTimeRange period = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  int tab = 0, generation = 0;
  bool loading = true, saving = false;
  String? error, selectedParameter, identity;
  late String operation;
  @override
  void initState() {
    super.initState();
    identity = ApiService.sessionIdentity;
    operation = service.command({})['operation_uuid'] as String;
    widget.api.sessionChanges?.addListener(sessionChanged);
    load();
  }

  void sessionChanged() {
    if (identity != ApiService.sessionIdentity) {
      generation++;
      if (mounted) {
        setState(() {
          parameters = [];
          rules = [];
          rows = [];
          error = 'Session terminée.';
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    widget.api.sessionChanges?.removeListener(sessionChanged);
    for (final c in fields.values) {
      c.dispose();
    }
    note.dispose();
    super.dispose();
  }

  Map<String, dynamic>? ruleFor(String id, DateTime at) {
    for (final r in rules) {
      if (r['parameter'] == id &&
          !DateTime.parse('${r['valid_from']}').isAfter(at)) {
        return r;
      }
    }
    return null;
  }

  Future<void> load() async {
    final ticket = ++generation, captured = ApiService.sessionIdentity;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var ps = await service.list(
        'technical/parameters/?species=${widget.species['id']}',
      );
      if (ps.where((p) => p['predefined'] == true).length < 5) {
        await service.send(
          'technical/setup/',
          service.command({'species': widget.species['id']}),
        );
        ps = await service.list(
          'technical/parameters/?species=${widget.species['id']}',
        );
      }
      final rs = await service.list('technical/rules/?lot=${widget.lot['id']}');
      final readings = await service.list(
        'technical/readings/?lot=${widget.lot['id']}&from=${hDay(period.start)}&to=${hDay(period.end)}',
      );
      if (!mounted ||
          ticket != generation ||
          captured != ApiService.sessionIdentity) {
        return;
      }
      const order = [
        'temperature',
        'humidity',
        'lighting',
        'ventilation',
        'housing',
        'water',
      ];
      ps.sort((a, b) {
        final ai = order.indexOf('${a['code']}'),
            bi = order.indexOf('${b['code']}');
        return (ai < 0 ? 100 : ai).compareTo(bi < 0 ? 100 : bi);
      });
      setState(() {
        parameters = ps;
        rules = rs;
        rows = readings;
        loading = false;
        selectedParameter ??=
            ps.where((p) => p['kind'] == 'NUMBER').firstOrNull?['id']
                as String?;
      });
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          loading = false;
          parameters = [];
          rules = [];
          rows = [];
          error = hError(e);
        });
      }
    }
  }

  Future<void> saveReading() async {
    final values = <Map<String, dynamic>>[];
    for (final p in parameters) {
      final id = '${p['id']}';
      if (ruleFor(id, occurred)?['visible'] == false) continue;
      final value = p['kind'] == 'BOOL'
          ? booleans[id]
          : fields[id]?.text.trim();
      if (value != null && value != '') {
        values.add({
          'parameter': id,
          'value': p['kind'] == 'NUMBER'
              ? '$value'.replaceAll(',', '.')
              : value,
        });
      }
    }
    if (values.isEmpty) {
      setState(() => error = 'Renseignez au moins une valeur.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final captured = ApiService.sessionIdentity;
    try {
      await service.send('technical/readings/', {
        'schema_version': 1,
        'operation_uuid': operation,
        'lot': widget.lot['id'],
        'occurred_at': occurred.toUtc().toIso8601String(),
        'values': values,
        'note': note.text.trim(),
      });
      if (!mounted || captured != ApiService.sessionIdentity) return;
      for (final c in fields.values) {
        c.clear();
      }
      booleans.clear();
      note.clear();
      operation = service.command({})['operation_uuid'] as String;
      setState(() => tab = 1);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = hError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> choosePeriod() async {
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      initialDateRange: period,
    );
    if (value != null) {
      setState(() => period = value);
      await load();
    }
  }

  Future<void> addParameter() async {
    final name = TextEditingController(), unit = TextEditingController();
    String kind = 'NUMBER';
    bool busy = false;
    String? failure;
    final op = service.command({});
    final route = DialogRoute<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => HDialog(
          title: 'Ajouter un paramètre',
          busy: busy,
          error: failure,
          children: [
            HField('Nom', name),
            DropdownButtonFormField<String>(
              initialValue: kind,
              isExpanded: true,
              decoration: const V2InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'NUMBER', child: Text('Numérique')),
                DropdownMenuItem(value: 'TEXT', child: Text('Qualitatif')),
                DropdownMenuItem(value: 'BOOL', child: Text('Oui / Non')),
              ],
              onChanged: busy ? null : (v) => update(() => kind = v!),
            ),
            const SizedBox(height: 18),
            HField('Unité (facultative)', unit),
          ],
          onSave: () async {
            update(() {
              busy = true;
              failure = null;
            });
            try {
              await service.send('technical/parameters/', {
                ...op,
                'species': widget.species['id'],
                'name': name.text.trim(),
                'kind': kind,
                'unit': unit.text.trim(),
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
    unit.dispose();
    if (mounted) await load();
  }

  Future<void> configure(Map<String, dynamic> p) async {
    final current = rules.where((r) => r['parameter'] == p['id']).firstOrNull;
    final lower = TextEditingController(
          text: current?['lower']?.toString() ?? '',
        ),
        upper = TextEditingController(
          text: current?['upper']?.toString() ?? '',
        );
    bool visible = current?['visible'] != false,
        alerts = current?['alerts_enabled'] == true,
        busy = false;
    String? failure;
    DateTime validFrom = DateTime.now();
    final op = service.command({});
    final route = DialogRoute<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => HDialog(
          title: '${p['name']}',
          busy: busy,
          error: failure,
          children: [
            HDateField(
              label: 'Applicable à partir du',
              value: validFrom,
              withTime: true,
              onChanged: (v) => update(() => validFrom = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Afficher pour ce lot'),
              value: visible,
              onChanged: busy ? null : (v) => update(() => visible = v!),
            ),
            if (p['kind'] == 'NUMBER') ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Avertissements visuels'),
                value: alerts,
                onChanged: busy ? null : (v) => update(() => alerts = v!),
              ),
              HField('Minimum (facultatif)', lower, numeric: true),
              HField('Maximum (facultatif)', upper, numeric: true),
            ],
          ],
          onSave: () async {
            update(() {
              busy = true;
              failure = null;
            });
            try {
              await service.send('technical/rules/', {
                ...op,
                'lot': widget.lot['id'],
                'parameter': p['id'],
                'valid_from': validFrom.toUtc().toIso8601String(),
                'expected_version': current?['version'] ?? 0,
                'visible': visible,
                'alerts_enabled': alerts,
                'lower': lower.text.trim().isEmpty
                    ? null
                    : lower.text.trim().replaceAll(',', '.'),
                'upper': upper.text.trim().isEmpty
                    ? null
                    : upper.text.trim().replaceAll(',', '.'),
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
    lower.dispose();
    upper.dispose();
    if (mounted) await load();
  }

  Widget valueField(Map<String, dynamic> p) {
    final id = '${p['id']}',
        label = '${p['name']}${p['unit'] == '' ? '' : ' (${p['unit']})'}';
    if (p['kind'] == 'BOOL') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: DropdownButtonFormField<bool>(
          key: ValueKey('boolean-$id-$operation'),
          isExpanded: true,
          initialValue: booleans[id],
          decoration: V2InputDecoration(labelText: label),
          items: const [
            DropdownMenuItem<bool>(value: null, child: Text('Non renseigné')),
            DropdownMenuItem(value: true, child: Text('Oui')),
            DropdownMenuItem(value: false, child: Text('Non')),
          ],
          onChanged: saving ? null : (v) => setState(() => booleans[id] = v),
        ),
      );
    }
    return HField(
      label,
      fields.putIfAbsent(id, () => TextEditingController()),
      numeric: p['kind'] == 'NUMBER',
    );
  }

  Widget periodButton() => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      onPressed: loading ? null : choosePeriod,
      icon: const Icon(Icons.date_range_outlined),
      label: Text('${hDate(period.start)} – ${hDate(period.end)}'),
    ),
  );
  Widget history() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      periodButton(),
      const SizedBox(height: 12),
      if (rows.isEmpty) const Text('Aucun relevé.'),
      for (final r in rows)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hDateTime(r['occurred_at']),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final v in r['values'] as List)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (v['alert'] == true)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            '${v['name']} : ${v['value'] is bool ? (v['value'] == true ? 'Oui' : 'Non') : v['value']} ${v['unit']}',
                          ),
                        ),
                      ],
                    ),
                  ),
                if ('${r['note']}'.isNotEmpty) Text('${r['note']}'),
              ],
            ),
          ),
        ),
    ],
  );
  Widget evolution() {
    final p = parameters.where((p) => p['id'] == selectedParameter).firstOrNull;
    final series = [
      for (final r in rows)
        {
          'at': r['occurred_at'],
          'value': (r['values'] as List)
              .where((v) => v['parameter'] == selectedParameter)
              .firstOrNull?['value'],
        },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        periodButton(),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: selectedParameter,
          decoration: const V2InputDecoration(labelText: 'Paramètre'),
          items: parameters
              .where((p) => p['kind'] == 'NUMBER')
              .map(
                (p) => DropdownMenuItem<String>(
                  value: '${p['id']}',
                  child: Text(
                    '${p['name']} (${p['unit']})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => selectedParameter = v),
        ),
        const SizedBox(height: 24),
        if (series.any((x) => x['value'] != null))
          Semantics(
            label: 'Évolution de ${p?['name']} en ${p?['unit']}',
            child: SizedBox(
              height: 240,
              child: CustomPaint(painter: NumericEvolutionPainter(series)),
            ),
          )
        else
          const Text('Aucune valeur numérique sur cette période.'),
      ],
    );
  }

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: addParameter,
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un paramètre'),
        ),
      ),
      const SizedBox(height: 16),
      for (final p in parameters)
        Card(
          child: ListTile(
            title: Text('${p['name']}'),
            subtitle: Text(
              '${p['kind'] == 'NUMBER'
                  ? p['unit']
                  : p['kind'] == 'BOOL'
                  ? 'Oui / Non'
                  : 'Qualitatif'}${ruleFor('${p['id']}', DateTime.now())?['visible'] == false ? ' · Masqué' : ''}',
            ),
            trailing: IconButton(
              tooltip: 'Configurer ${p['name']}',
              icon: const Icon(Icons.tune),
              onPressed: () => configure(p),
            ),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => V2Scaffold(
    appBar: V2AppBar(
      title: const Text('Technique'),
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
                  'Nouveau relevé',
                  'Historique',
                  'Évolution',
                  'Paramètres et seuils',
                ].asMap().entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: tab == e.key,
                    onSelected: (_) => setState(() => tab = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            HError(error),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (tab == 0) ...[
              HDateField(
                label: 'Date et heure',
                value: occurred,
                withTime: true,
                onChanged: (v) => setState(() => occurred = v),
              ),
              for (final p in parameters)
                if (ruleFor('${p['id']}', occurred)?['visible'] != false)
                  valueField(p),
              HField('Observations (facultatives)', note, lines: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: saving ? null : saveReading,
                  icon: const Icon(Icons.check),
                  label: Text(saving ? 'Enregistrement…' : 'Enregistrer'),
                ),
              ),
            ] else if (tab == 1)
              history()
            else if (tab == 2)
              evolution()
            else
              settings(),
          ],
        ),
      ),
    ),
  );
}

class NumericEvolutionPainter extends CustomPainter {
  NumericEvolutionPainter(this.series);
  final List<Map<String, dynamic>> series;
  @override
  void paint(Canvas canvas, Size size) {
    final rows = [...series]
      ..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    final values = rows
        .where((r) => r['value'] != null)
        .map((r) => double.tryParse('${r['value']}'))
        .whereType<double>()
        .toList();
    if (values.isEmpty) return;
    final min = values.reduce((a, b) => a < b ? a : b),
        max = values.reduce((a, b) => a > b ? a : b),
        span = max == min ? 1.0 : max - min;
    String axis(double v) => v != 0 && (v.abs() < 0.01 || v.abs() >= 100000)
        ? v.toStringAsExponential(2)
        : v.toStringAsFixed(2);
    double labelWidth(String value) {
      final p = TextPainter(
        text: TextSpan(
          text: value,
          style: const TextStyle(fontFamily: 'Roboto', fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return p.width;
    }

    final left =
            [
              labelWidth(axis(min)),
              labelWidth(axis(max)),
            ].reduce((a, b) => a > b ? a : b) +
            10,
        right = size.width - 14,
        top = 16.0,
        bottom = size.height - 36;
    final first = DateTime.parse(
          '${rows.first['at']}',
        ).millisecondsSinceEpoch.toDouble(),
        last = DateTime.parse(
          '${rows.last['at']}',
        ).millisecondsSinceEpoch.toDouble();
    canvas.drawLine(
      Offset(left, top),
      Offset(left, bottom),
      Paint()..color = V2Colors.border,
    );
    canvas.drawLine(
      Offset(left, bottom),
      Offset(right, bottom),
      Paint()..color = V2Colors.border,
    );
    void text(String value, Offset at) {
      final p = TextPainter(
        text: TextSpan(
          text: value,
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            color: V2Colors.muted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      p.paint(canvas, at);
    }

    text(axis(max), Offset(0, top));
    text(axis(min), Offset(0, bottom - 14));
    text(hDate(rows.first['at']), Offset(left, bottom + 12));
    if (right - left > 200) {
      text(hDate(rows.last['at']), Offset(right - 76, bottom + 12));
    }
    final path = Path();
    bool pen = false;
    for (final r in rows) {
      final v = double.tryParse('${r['value']}');
      if (v == null) {
        pen = false;
        continue;
      }
      final t = DateTime.parse('${r['at']}').millisecondsSinceEpoch.toDouble();
      final x =
              left +
              (last == first ? 0.5 : (t - first) / (last - first)) *
                  (right - left),
          y = bottom - (v - min) / span * (bottom - top);
      if (pen) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        pen = true;
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = V2Colors.green);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = V2Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant NumericEvolutionPainter old) =>
      old.series != series;
}
