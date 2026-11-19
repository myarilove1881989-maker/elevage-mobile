import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/design_system_v2.dart';
import '../widgets/v2_components.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';

String feedDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  if (d == null) return 'Date inconnue';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String feedWhen(Map row) {
  if (row['time_precision'] == 'DATE') {
    final parts = '${row['business_date']}'.split('-');
    return parts.length == 3
        ? '${parts[2]}/${parts[1]}/${parts[0]} (heure inconnue)'
        : 'Date seule';
  }
  final at = DateTime.tryParse('${row['occurred_at']}')?.toLocal();
  if (at == null) return 'Date inconnue';
  return '${feedDate(row['occurred_at'])} à ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

String feedMovementLabel(dynamic value) =>
    const {
      'AQUA_FEED_PURCHASE': 'Achat d’aliment',
      'AQUA_FEED_DISTRIB': 'Distribution aux poissons',
      'AQUA_FEED_TRANSFER': 'Transfert de réserve',
      'FEED_RECEIPT': 'Entrée d’aliment',
      'FEED_DISTRIBUTION': 'Distribution à l’élevage',
      'REVERSE': 'Compensation',
    }[value] ??
    'Mouvement de stock';
String feedDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String feedDecimal(String value) => value.trim().replaceAll(',', '.');
String feedPercent(dynamic exact) {
  if (exact is! Map) return 'Données insuffisantes';
  final text = '${exact['decimal'] ?? exact['value'] ?? ''}';
  if (text.isNotEmpty) {
    return text.length > 14 ? '${text.substring(0, 14)}…' : text;
  }
  return '${exact['numerator']}/${exact['denominator']}';
}

Widget feedCard(List<Widget> children) => Card(
  color: Colors.white,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: const BorderSide(color: V2Colors.border),
  ),
  child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  ),
);
Widget feedingOverview(Map data) => feedCard([
  const Text(
    'Alimentation',
    style: TextStyle(fontWeight: FontWeight.bold, color: V2Colors.navy),
  ),
  Text(
    '${data['distributed_kg']} kg distribués · ${feedDate(data['from'])} au ${feedDate(data['to'])}',
  ),
  Text(
    'Stock commun actuel : ${data['common_stock_kg']} kg (toute l’exploitation)',
  ),
  Text(
    'Consommation estimée : ${data['estimated_consumed_kg'] == null ? 'Données insuffisantes' : '${data['estimated_consumed_kg']} kg'}',
  ),
  for (final row in (data['by_product'] as List? ?? []).take(3))
    Text('${row['name']} : ${row['quantity_kg']} kg'),
]);

class FeedingPanel extends StatefulWidget {
  const FeedingPanel({
    super.key,
    required this.service,
    required this.owner,
    required this.rights,
    required this.installations,
    required this.cohorts,
    this.onChanged,
    this.initialInstallation,
    this.initialCohort,
    this.initialAction,
  });
  final AquaticService service;
  final bool owner;
  final List<String> rights;
  final List<Map<String, dynamic>> installations, cohorts;
  final Future<void> Function()? onChanged;
  final String? initialInstallation,initialCohort,initialAction;
  @override
  State<FeedingPanel> createState() => _FeedingPanelState();
}

class _FeedingPanelState extends State<FeedingPanel> {
  bool openedInitial=false;
  Map<String, dynamic>? catalog, summary;
  List<Map<String, dynamic>> distributions = [], purchases = [], movements = [];
  bool busy = true;
  String? error, installation, cohort, product;
  String section = 'Distributions';
  DateTime end = DateTime.now(),
      start = DateTime.now().subtract(const Duration(days: 6));
  int generation = 0;
  @override
  void initState() {
    super.initState();
    installation=widget.initialInstallation;cohort=widget.initialCohort;
    load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  String name(dynamic id) =>
      [
        ...widget.installations,
        ...widget.cohorts,
      ].where((r) => r['id'] == id).map((r) => '${r['name']}').firstOrNull ??
      '$id';
  String query({bool population = true}) =>
      '?${Uri(queryParameters: {'from': DateTime(start.year, start.month, start.day).toUtc().toIso8601String(), 'to': DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toUtc().toIso8601String(), 'product': ?product, if (population) 'installation': ?installation, if (population) 'cohort': ?cohort}).query}';
  Future<void> load() async {
    final epoch = ++generation, identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
      catalog = null;
      summary = null;
      distributions = [];
      purchases = [];
      movements = [];
    });
    try {
      final c = await widget.service.read('feed-products/');
      final result = await Future.wait<dynamic>([
        widget.service.read('feed-summary/${query()}'),
        widget.service.list('feed-distributions/${query()}'),
        widget.service.list('feed-stock-history/${query(population: false)}'),
        if (c['can_read_purchases'] == true)
          widget.service.list('feed-purchases/${query(population: false)}'),
      ]);
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        catalog = c;
        summary = result[0];
        distributions = result[1];
        movements = result[2];
        purchases = result.length > 3 ? result[3] : [];
        busy = false;
      });
      if(widget.initialAction!=null&&!openedInitial){openedInitial=true;WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)edit(widget.initialAction!);});}
    } catch (_) {
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        busy = false;
        error =
            'Alimentation indisponible. Vérifiez la connexion et vos droits, puis actualisez.';
      });
    }
  }

  Future<void> edit(String kind) async {
    final identity = ApiService.sessionIdentity;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FeedEditor(
        service: widget.service,
        kind: kind,
        owner: widget.owner,
        catalog: catalog!,
        installations: widget.installations,
        cohorts: widget.cohorts,
      ),
    );
    if (changed == true && mounted && identity == ApiService.sessionIdentity) {
      await load();
      if (mounted && identity == ApiService.sessionIdentity) {
        await widget.onChanged?.call();
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
          'Alimentation',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: V2Colors.navy,
          ),
        ),
        const Text(
          'Stock partagé avec l’élevage. Les distributions ne créent aucune nouvelle dépense. En ligne uniquement.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.rights.contains('aquatic.feed.distribute'))
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: V2Colors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy || catalog == null
                    ? null
                    : () => edit('DISTRIBUTION'),
                icon: const Icon(Icons.set_meal, color: V2Colors.green),
                label: const Text('Distribuer un aliment'),
              ),
            if (catalog?['can_purchase'] == true)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: V2Colors.navy,
                  foregroundColor: Colors.white,
                ),
                onPressed: busy ? null : () => edit('PURCHASE'),
                icon: const Icon(Icons.shopping_bag, color: V2Colors.green),
                label: const Text('Acheter un aliment'),
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
            filter('Bassin', installation, widget.installations, (v) {
              installation = v;
              cohort = null;
            }),
            filter('Cohorte', cohort, widget.cohorts, (v) => cohort = v),
            filter(
              'Aliment',
              product,
              List<Map<String, dynamic>>.from(catalog?['products'] ?? []),
              (v) => product = v,
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : period,
              icon: const Icon(Icons.date_range, color: V2Colors.green),
              label: Text(
                '${feedDate(start.toIso8601String())} au ${feedDate(end.toIso8601String())}',
              ),
            ),
          ],
        ),
        if (summary != null) ...[
          feedCard([
            Text(
              '${summary!['distributed_kg']} kg distribués sur la période',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: V2Colors.navy,
              ),
            ),
            Text(
              'Consommation estimée : ${summary!['estimated_consumed_kg'] == null ? 'Données insuffisantes' : '${summary!['estimated_consumed_kg']} kg'}',
            ),
            if (summary!['consumption_status'] == 'PARTIAL')
              Text(
                'Saisie partielle : ${summary!['known_consumed_kg']} kg estimés sur les seuls relevés avec restes connus.',
              ),
            if (cohort != null)
              Text(
                '${summary!['unassigned_distributed_kg']} kg au bassin sans cohorte identifiée, exclus du total de cette cohorte.',
              ),
            Text(
              'Stock commun actuel : ${summary!['common_stock_kg']} kg · toute l’exploitation, hors réserves',
            ),
            Text(
              (summary!['biomass_comparison'] as Map)['status'] == 'INDICATIVE'
                  ? 'Aliment / biomasse estimée : ${feedPercent((summary!['biomass_comparison'] as Map)['feed_percent'])} % · indicatif sur la période'
                  : 'Aliment / biomasse : Données insuffisantes',
            ),
            const Text('FCR non calculé. Aucune ration biologique proposée.'),
          ]),
          feedCard([
            const Text(
              'Quantités distribuées par jour (kg)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if ((summary!['by_day'] as List).isEmpty)
              const Text('Aucune distribution sur cette période.')
            else
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: FeedChart(
                    List<Map<String, dynamic>>.from(summary!['by_day']),
                  ),
                ),
              ),
            const Text(
              'Aliments les plus utilisés',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final r in summary!['by_product'] as List)
              Text('${r['name']} : ${r['quantity_kg']} kg'),
          ]),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final tab in [
              'Distributions',
              'Stock',
              'Mouvements',
              if (catalog?['can_read_purchases'] == true) 'Achats',
            ])
              ChoiceChip(
                label: Text(tab),
                selected: section == tab,
                selectedColor: V2Colors.navy,
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                side: const BorderSide(color: V2Colors.border),
                labelStyle: TextStyle(
                  color: section == tab ? Colors.white : V2Colors.navy,
                ),
                onSelected: (_) => setState(() => section = tab),
              ),
          ],
        ),
        if (catalog != null && section == 'Stock') ...[
          const Text(
            'Stock actuel de l’exploitation, indépendant de la période et des filtres de population. Les réserves sont indisponibles aux poissons tant que leur propriétaire ne les libère pas.',
          ),
          if (widget.owner && catalog!['can_manage_reserves'] == true)
            OutlinedButton(
              onPressed: () => edit('RESERVE'),
              child: const Text('Gérer les réserves'),
            ),
          for (final r in catalog!['products'] as List)
            feedCard([
              Text(
                '${r['name']}${r['archived'] == true ? ' (archivé)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Disponible commun : ${r['common_kg']} kg · physique total : ${r['physical_kg']} kg',
              ),
              if (r['aquatic_used'] == true)
                const Text('Utilisé en pisciculture'),
              for (final pool in r['reserves'] as List)
                Text('${pool['label']} : ${pool['quantity_kg']} kg'),
            ]),
        ],
        if (section == 'Distributions') ...[
          if (!busy && error == null && distributions.isEmpty)
            const Text('Aucune distribution pour ces filtres.'),
          for (final r in distributions.reversed)
            feedCard([
              Text(
                '${r['product_name']} · ${r['quantity_kg']} kg',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${feedWhen(r)} · ${name(r['installation'])} · ${r['cohort'] == null ? 'Bassin global, sans attribution à une cohorte' : name(r['cohort'])}',
              ),
              Text(
                'Restes : ${r['leftovers_kg'] == null ? 'non renseignés' : '${r['leftovers_kg']} kg'} · consommation estimée : ${r['estimated_consumed_kg'] == null ? 'inconnue' : '${r['estimated_consumed_kg']} kg'}',
              ),
              Text(
                (r['analysis'] as Map?)?['status'] == 'INDICATIVE'
                    ? 'Aliment / biomasse à la date : ${feedPercent(r['analysis']['feed_percent'])} % (indicatif)'
                    : 'Biomasse : Données insuffisantes',
              ),
              Text(
                'Auteur : ${r['actor']} · enregistré le ${feedDate(r['recorded_at'])}',
              ),
              if ('${r['note'] ?? ''}'.isNotEmpty) Text('${r['note']}'),
            ]),
        ],
        if (section == 'Achats') ...[
          const Text(
            'Achats du stock commun de l’exploitation : période et aliment sélectionnés. Les filtres bassin et cohorte ne s’appliquent pas.',
          ),
          if (purchases.isEmpty) const Text('Aucun achat sur cette période.'),
          for (final r in purchases.reversed)
            feedCard([
              Text('${r['product_name']} · +${r['quantity_kg']} kg'),
              Text(
                '${feedWhen(r)} · dépense n°${r['expense_id']} : ${r['amount']}',
              ),
              Text('Auteur : ${r['actor']} · ${r['note'] ?? ''}'),
            ]),
        ],
        if (section == 'Mouvements') ...[
          const Text(
            'Registre partagé : tous les mouvements de l’exploitation sur la période, hors filtres bassin et cohorte.',
          ),
          if (movements.isEmpty)
            const Text('Aucun mouvement sur cette période.'),
          for (final r in movements.reversed)
            feedCard([
              Text('${r['product_name']} · ${r['quantity_kg']} kg'),
              Text(
                '${feedWhen(r)} · ${r['scope'] == 'FARM_COMMON' ? 'Commun' : 'Réservé'} · ${feedMovementLabel(r['operation_kind'])}',
              ),
              Text('Auteur : ${r['actor']}'),
            ]),
        ],
      ],
    ),
  );
}

class FeedChart extends CustomPainter {
  FeedChart(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty || size.width < 60) return;
    final maxValue = rows
        .map((r) => double.tryParse('${r['quantity_kg']}') ?? 0)
        .fold<double>(0, math.max);
    final width = size.width - 52, height = size.height - 45;
    final bar = width / rows.length;
    final paint = Paint()..color = V2Colors.green;
    for (var i = 0; i < rows.length; i++) {
      final value = double.tryParse('${rows[i]['quantity_kg']}') ?? 0;
      final h = maxValue == 0 ? 0.0 : value / maxValue * height;
      canvas.drawRect(
        Rect.fromLTWH(44 + i * bar, height - h, bar * 0.7, h),
        paint,
      );
      if (i == 0 || i == rows.length - 1 || rows.length <= 4) {
        final label = TextPainter(
          text: TextSpan(
            text: '${rows[i]['date']}'.substring(5),
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 11,
              color: V2Colors.navy,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: bar + 24);
        label.paint(canvas, Offset(44 + i * bar, height + 5));
      }
    }
    final y = TextPainter(
      text: TextSpan(
        text: '$maxValue kg',
        style: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 11,
          color: V2Colors.navy,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 43);
    y.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant FeedChart oldDelegate) =>
      oldDelegate.rows != rows;
}

class FeedEditor extends StatefulWidget {
  const FeedEditor({
    super.key,
    required this.service,
    required this.kind,
    required this.owner,
    required this.catalog,
    required this.installations,
    required this.cohorts,
  });
  final AquaticService service;
  final String kind;
  final bool owner;
  final Map<String, dynamic> catalog;
  final List<Map<String, dynamic>> installations, cohorts;
  @override
  State<FeedEditor> createState() => _FeedEditorState();
}

class _FeedEditorState extends State<FeedEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  TextEditingController c(String key) =>
      fields.putIfAbsent(key, () => TextEditingController());
  String? product, site, cohort, category, source, target;
  DateTime at = DateTime.now();
  bool timeKnown = true,
      newProduct = false,
      newCategory = false,
      busy = false,
      uncertain = false;
  String? error;
  Map<String, dynamic>? pending;
  bool get purchase => widget.kind == 'PURCHASE';
  bool get reserve => widget.kind == 'RESERVE';
  bool get locked => busy || uncertain;
  List<Map<String, dynamic>> get products => List<Map<String, dynamic>>.from(
    widget.catalog['products'],
  ).where((r) => r['archived'] != true).toList();
  Map<String, dynamic>? get selected =>
      products.where((r) => r['id'] == product).firstOrNull;
  List<Map<String, dynamic>> get pools =>
      List<Map<String, dynamic>>.from(selected?['reserves'] ?? []);
  Map<String, dynamic> pool(String? key) {
    if (key == null || key == 'common') return {'species': null, 'lot': null};
    final pieces = key.split(':');
    return {
      'species': int.parse(pieces[0]),
      'lot': pieces[1] == 'null' ? null : int.parse(pieces[1]),
    };
  }

  String poolKey(Map row) =>
      row['species'] == null ? 'common' : '${row['species']}:${row['lot']}';
  @override
  void dispose() {
    for (final v in fields.values) {
      v.dispose();
    }
    super.dispose();
  }

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
          const DropdownMenuItem(value: null, child: Text('Bassin global')),
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
  Widget text(
    String key,
    String label, {
    bool decimal = false,
    int scale = 3,
    bool optional = false,
    bool zero = false,
    int length = 500,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: c(key),
      enabled: !locked,
      maxLength: decimal ? null : length,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: V2InputDecoration(labelText: label),
      validator: (value) {
        final v = (value ?? '').trim();
        if (v.isEmpty) return optional ? null : 'Champ requis';
        if (decimal) {
          final n = feedDecimal(v);
          if (!RegExp('^[0-9]+(?:[.][0-9]{1,$scale})?\u0024').hasMatch(n)) {
            return 'Nombre décimal, $scale chiffres après la virgule au maximum';
          }
          if (!zero && BigInt.parse(n.replaceAll('.', '')) == BigInt.zero) {
            return 'Quantité strictement positive';
          }
        }
        return null;
      },
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
    if (timeKnown || reserve) {
      return {
        'occurred_at': at.toUtc().toIso8601String(),
        if (!reserve) 'time_precision': 'DATETIME',
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

  Map<String, dynamic> payload() => {
    ...moment(),
    'unit': 'kg',
    'quantity_kg': feedDecimal(c('quantity').text),
    if (purchase) ...{
      if (newProduct)
        'new_product': {
          'id': widget.service.command({})['operation_uuid'],
          'name': c('name').text.trim(),
        }
      else
        'product': product,
      if (newCategory)
        'new_category': c('category_name').text.trim()
      else
        'category': int.parse(category!),
      'amount': feedDecimal(c('amount').text),
      'note': c('note').text.trim(),
    } else if (reserve) ...{
      'product': product,
      'source': pool(source),
      'target': pool(target),
      'reason': c('reason').text.trim(),
    } else ...{
      'product': product,
      'installation': site,
      'cohort': cohort,
      'leftovers_kg': c('leftovers').text.trim().isEmpty
          ? null
          : feedDecimal(c('leftovers').text),
      'note': c('note').text.trim(),
    },
  };
  Future<void> save() async {
    if (!uncertain && !form.currentState!.validate()) return;
    final identity = ApiService.sessionIdentity;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      pending ??= widget.service.command(payload());
      await widget.service.send(
        purchase
            ? 'feed-purchases/'
            : reserve
            ? 'feed-reserves/'
            : 'feed-distributions/',
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
            ? 'Enregistrement refusé. Vérifiez le stock commun, les droits, la présence à la date choisie et les valeurs. ${e.message}'
            : 'Réponse non reçue. Réessayez la même opération : elle ne sera pas déduite deux fois.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceRows = pools
        .map(
          (r) => <String, dynamic>{
            'id': poolKey(r),
            'name': '${r['label']} (${r['quantity_kg']} kg)',
          },
        )
        .toList();
    final targetRows = <Map<String, dynamic>>[
      {'id': 'common', 'name': 'Commun à l’exploitation'},
      for (final r in widget.catalog['species'] as List)
        {'id': '${r['id']}:null', 'name': 'Réserve espèce : ${r['name']}'},
      for (final r in widget.catalog['lots'] as List)
        {
          'id': '${r['species']}:${r['id']}',
          'name': 'Réserve lot : ${r['name']}',
        },
    ];
    return Theme(
      data: designSystemV2(Theme.of(context)),
      child: V2AlertDialog(
        backgroundColor: V2Colors.background,
        title: Text(
          purchase
              ? 'Acheter un aliment'
              : reserve
              ? 'Gérer les réserves'
              : 'Distribuer un aliment',
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
                  Text(
                    purchase
                        ? 'Une seule dépense et une entrée dans le stock commun.'
                        : reserve
                        ? 'Transfert explicite dans le même stock. Aucune dépense.'
                        : 'Déduction du stock commun, sans nouvelle dépense. Les restes ne retournent pas en stock.',
                  ),
                  const SizedBox(height: 12),
                  if (purchase && widget.owner)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Créer un nouvel aliment'),
                      value: newProduct,
                      onChanged: locked
                          ? null
                          : (v) => setState(() => newProduct = v),
                    ),
                  if (newProduct)
                    text('name', 'Nom du nouvel aliment', length: 120)
                  else
                    select('Aliment existant', product, products, (v) {
                      product = v;
                      source = null;
                      target = null;
                    }),
                  if (selected != null)
                    Text(
                      'Disponible commun : ${selected!['common_kg']} kg · total physique : ${selected!['physical_kg']} kg',
                    ),
                  if (purchase) ...[
                    if (widget.owner)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Créer une catégorie de dépense'),
                        value: newCategory,
                        onChanged: locked
                            ? null
                            : (v) => setState(() => newCategory = v),
                      ),
                    if (newCategory)
                      text('category_name', 'Nom de la catégorie', length: 50)
                    else
                      select(
                        'Catégorie alimentaire',
                        category,
                        List<Map<String, dynamic>>.from(
                          widget.catalog['categories'],
                        ),
                        (v) => category = v,
                      ),
                    text(
                      'amount',
                      'Montant de la dépense',
                      decimal: true,
                      scale: 2,
                      zero: true,
                    ),
                  ],
                  if (!purchase && !reserve) ...[
                    select(
                      'Bassin concerné',
                      site,
                      widget.installations
                          .where((r) => r['status'] == 'ACTIVE')
                          .toList(),
                      (v) {
                        site = v;
                        cohort = null;
                      },
                    ),
                    select(
                      'Cohorte (facultative)',
                      cohort,
                      widget.cohorts
                          .where((r) => r['status'] == 'OPEN')
                          .toList(),
                      (v) => cohort = v,
                      optional: true,
                    ),
                    const Text(
                      'Sans cohorte identifiée, la quantité reste attribuée au bassin entier. La présence est vérifiée à la date de distribution.',
                    ),
                  ],
                  if (reserve) ...[
                    select(
                      'Réserve de départ',
                      source,
                      sourceRows,
                      (v) => source = v,
                    ),
                    select(
                      'Destination autorisée',
                      target,
                      targetRows,
                      (v) => target = v,
                    ),
                    text('reason', 'Motif du transfert'),
                  ],
                  text(
                    'quantity',
                    purchase
                        ? 'Quantité achetée (kg)'
                        : reserve
                        ? 'Quantité transférée (kg)'
                        : 'Quantité distribuée (kg)',
                    decimal: true,
                  ),
                  if (!purchase && !reserve)
                    text(
                      'leftovers',
                      'Restes observés (kg, facultatif)',
                      decimal: true,
                      optional: true,
                      zero: true,
                    ),
                  if (!purchase && !reserve)
                    const Text(
                      'Vide = consommation inconnue. Zéro = aucun reste observé. La consommation reste une estimation.',
                    ),
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
                      if (timeKnown || reserve)
                        OutlinedButton(
                          onPressed: locked ? null : hour,
                          child: Text(
                            'Heure : ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                          ),
                        ),
                    ],
                  ),
                  if (!reserve)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Heure connue'),
                      value: timeKnown,
                      onChanged: locked
                          ? null
                          : (v) => setState(() => timeKnown = v!),
                    ),
                  if (!timeKnown && !reserve)
                    const Text(
                      'Date seule conservée. Pour le contrôle du stock et des présences, le début de cette journée doit être compatible avec les opérations déjà enregistrées.',
                    ),
                  if (!reserve)
                    text(
                      'note',
                      'Note (facultative)',
                      optional: true,
                      length: purchase ? 255 : 500,
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
