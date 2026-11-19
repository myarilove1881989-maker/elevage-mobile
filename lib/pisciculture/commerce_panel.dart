import 'package:flutter/material.dart';
import '../theme/design_system_v2.dart';
import '../widgets/v2_components.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/invoice_pdf_service.dart';
import 'aquatic_service.dart';
import 'feeding_panel.dart' show feedCard, feedWhen;

Widget commerceCard(BuildContext context, Widget child) => feedCard([child]);
String commerceUnit(dynamic u) => u == 'KG' ? 'kg' : 'poissons';
String commerceValue(dynamic v) => v == null ? 'Non renseigné' : '$v';
String commerceError(Object e) {
  final s = '$e';
  if (s.contains('HEALTH_REVIEW_STALE')) {
    return 'La situation a changé. Relisez les précautions sanitaires et confirmez à nouveau.';
  }
  if (s.contains('HEALTH_RECORDED_RESTRICTION')) {
    return 'Un traitement en cours ou un délai documenté actif empêche cette confirmation.';
  }
  if (s.contains('CAPACITY') || s.contains('TIMELINE')) {
    return 'Stock insuffisant ou chronologie incompatible. Actualisez les quantités et les dates.';
  }
  if (s.contains('CORRECTION') || s.contains('DEPENDENTS')) {
    return 'Cette opération a des suites. Une correction motivée doit être examinée avant tout changement financier.';
  }
  return 'Opération refusée. Vérifiez vos droits, les références, les dates et les mesures.';
}

String? commerceTotal(String q, String price) {
  BigInt? scaled(String s, int scale) {
    final p = s.trim().replaceAll(',', '.').split('.');
    if (p.length > 2 ||
        !RegExp(r'^\d+$').hasMatch(p[0]) ||
        (p.length == 2 &&
            (p[1].length > scale || !RegExp(r'^\d*$').hasMatch(p[1])))) {
      return null;
    }
    return BigInt.parse(p[0]) * BigInt.from(10).pow(scale) +
        BigInt.parse((p.length == 2 ? p[1] : '').padRight(scale, '0'));
  }

  final a = scaled(q, 6), b = scaled(price, 2);
  if (a == null || b == null) return null;
  final cents = (a * b + BigInt.from(500000)) ~/ BigInt.from(1000000);
  return '${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
}

class CommercePanel extends StatefulWidget {
  const CommercePanel({
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
    this.initialSection='stock',
    this.onChanged,
  });
  final AquaticService service;
  final bool owner;
  final List<String> rights;
  final List<Map<String, dynamic>> installations, cohorts, species;
  final String? initialInstallation, initialCohort, initialAction;
  final String initialSection;
  final Future<void> Function()? onChanged;
  @override
  State<CommercePanel> createState() => _CommercePanelState();
}

class _CommercePanelState extends State<CommercePanel> {
  List<Map<String, dynamic>> harvests = [], history = [], clients = [];
  String section = 'stock';
  String? installation, cohort, species, client, status, error;
  DateTime start = DateTime.now().subtract(const Duration(days: 29)),
      end = DateTime.now();
  int generation = 0;
  bool loading = true;
  bool openedInitial = false;
  bool allows(String s) => widget.owner || widget.rights.contains(s);
  @override
  void initState() {
    super.initState();
    section = widget.initialSection;
    installation = widget.initialInstallation;
    cohort = widget.initialCohort;
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
    try {
      final filter = <String, String>{
        'installation': ?installation,
        'cohort': ?cohort,
        'species': ?species,
        'client': ?client,
        'status': ?status,
      };
      final query = Uri(queryParameters: filter).query;
      final hs = await widget.service.list(
        'harvests/${query.isEmpty ? '' : '?$query'}',
      );
      final hist = await widget.service.list(
        'commerce-history/?${Uri(queryParameters: {...filter, 'from': DateTime(start.year, start.month, start.day).toUtc().toIso8601String(), 'to': DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toUtc().toIso8601String()}).query}',
      );
      final cs = await widget.service.list('commerce-clients/');
      if (!mounted ||
          epoch != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      setState(() {
        harvests = hs;
        history = hist;
        clients = cs;
        loading = false;
      });
      if (widget.initialAction != null && !openedInitial) {
        openedInitial = true;
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
        harvests = [];
        history = [];
        clients = [];
        loading = false;
        error = 'Lecture impossible. Actualisez avant de poursuivre.';
      });
    }
  }

  Future<void> edit(String mode, {Map<String, dynamic>? row}) async {
    final identity = ApiService.sessionIdentity;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => CommerceEditor(
        service: widget.service,
        mode: mode,
        installations: widget.installations,
        cohorts: widget.cohorts,
        harvests: harvests,
        clients: clients,
        row: row,
        initialInstallation: installation,
        initialCohort: cohort,
      ),
    );
    if (result == true && mounted && identity == ApiService.sessionIdentity) {
      await widget.onChanged?.call();
      if (mounted && identity == ApiService.sessionIdentity) await load();
    }
  }

  Future<void> details(Map<String, dynamic> h) async {
    final identity = ApiService.sessionIdentity;
    try {
      final data = await widget.service.read('harvests/${h['id']}/');
      if (!mounted || identity != ApiService.sessionIdentity) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => V2AlertDialog(
          backgroundColor: V2Colors.background,
          title: const Text('Traçabilité de la récolte'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${data['cohort_name']} · ${data['installation_name']}\nRécolte : ${feedWhen(data)}\nDébit vivant confirmé : ${data['live_count']} poissons\nPoids : ${commerceValue(data['mass_kg'])} kg · ${data['mass_quality'] == 'MEASURED'
                        ? 'Mesuré'
                        : data['mass_quality'] == 'ESTIMATED'
                        ? 'Estimé'
                        : 'Non renseigné'}\nConservation : ${data['storage_place']} · ${data['storage_mode']}\n${data['conservation_note']}',
                  ),
                  for (final raw in data['movements'] as List? ?? []) ...[
                    const Divider(),
                    Text(
                      '${raw['kind'] == 'SALE'
                          ? 'Vente'
                          : raw['kind'] == 'LOSS'
                          ? 'Perte post-récolte'
                          : raw['kind'] == 'VOID'
                          ? 'Annulation'
                          : 'Demande de correction'} · ${feedWhen(raw)}\nQuantité : ${commerceValue(raw['quantity'])} ${commerceUnit(data['stock_unit'])}\n${raw['reason'] ?? ''}\n${raw['note'] ?? ''}',
                    ),
                    if (raw['invoice'] != null) ...[
                      Text(
                        '${raw['invoice']['invoice_reference']} · ${raw['invoice']['client_name']}\nFacturé : ${raw['invoice']['montant_total']} · Payé : ${raw['invoice']['montant_paye']} · Reste : ${raw['invoice']['reste']}',
                      ),
                      for (final p in raw['invoice']['payments'] as List? ?? [])
                        Text(
                          'Paiement ${p['id']} : ${p['amount']} · ${p['date']}',
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                await InvoicePdfService.openInvoice(
                                  sale: Map<String, dynamic>.from(
                                    raw['invoice'],
                                  ),
                                  customerName:
                                      '${raw['invoice']['client_name']}',
                                  customerPhone:
                                      '${raw['invoice']['client_phone']}',
                                  languageCode: 'fr',
                                );
                              } catch (_) {
                                if (dialog.mounted) {
                                  ScaffoldMessenger.maybeOf(
                                    dialog,
                                  )?.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Ouverture de facture impossible.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('Facture'),
                          ),
                          if (allows('cash.create'))
                            OutlinedButton(
                              onPressed: () {
                                Navigator.pop(dialog);
                                edit(
                                  'PAYMENT',
                                  row: Map<String, dynamic>.from(
                                    raw['invoice'],
                                  ),
                                );
                              },
                              child: const Text('Enregistrer un paiement'),
                            ),
                          if (widget.owner)
                            OutlinedButton(
                              onPressed: () {
                                Navigator.pop(dialog);
                                edit(
                                  'CORRECTION',
                                  row: {...h, 'target': raw['id']},
                                );
                              },
                              child: const Text('Demander une correction'),
                            ),
                        ],
                      ),
                    ],
                    if (widget.owner &&
                        raw['kind'] == 'LOSS' &&
                        raw['canceled'] != true)
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(dialog);
                          edit('VOID', row: {...h, 'target': raw['id']});
                        },
                        child: const Text('Annuler cette perte'),
                      ),
                  ],
                  if (widget.owner)
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialog);
                        edit('VOID', row: h);
                      },
                      child: const Text('Annuler la récolte sans suite'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      if (mounted && identity == ApiService.sessionIdentity) await load();
    } catch (e) {
      if (mounted && identity == ApiService.sessionIdentity) {
        setState(() => error = commerceError(e));
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
      isExpanded: true,
      initialValue: value ?? '',
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('Tous')),
        for (final r in rows)
          DropdownMenuItem(
            value: '${r['id']}',
            child: Text(
              '${r['name'] ?? r['nom']}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        change(v == '' ? null : v);
        load();
      },
    ),
  );
  bool get billingView=>['clients','invoices','payments','balances'].contains(section);
  List<Map<String,dynamic>> get invoices {
    final found=<String,Map<String,dynamic>>{};
    for(final movement in history){final raw=movement['invoice'];if(raw is Map){final invoice=Map<String,dynamic>.from(raw);found['${invoice['id']}']=invoice;}}
    return found.values.toList();
  }
  Widget invoiceCard(Map<String,dynamic> invoice)=>commerceCard(context,Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('${invoice['invoice_reference']} · ${invoice['client_name']}',style:Theme.of(context).textTheme.titleMedium),
    const SizedBox(height:8),Text('Facturé : ${invoice['montant_total']} · Payé : ${invoice['montant_paye']} · Solde : ${invoice['reste']}'),
    if(section=='payments')for(final payment in invoice['payments'] as List? ?? [])Text('Paiement ${payment['date']} : ${payment['amount']}'),
    const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[
      OutlinedButton(onPressed:()async{try{await InvoicePdfService.openInvoice(sale:invoice,customerName:'${invoice['client_name']}',customerPhone:'${invoice['client_phone']}',languageCode:'fr');}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ouverture de facture impossible.')));}},child:const Text('Facture')),
      if(allows('cash.create'))OutlinedButton(onPressed:()=>edit('PAYMENT',row:invoice),child:const Text('Enregistrer un paiement')),
    ]),
  ]));
  @override
  Widget build(BuildContext context) => Theme(
    data: designSystemV2(Theme.of(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          {'clients':'Clients','invoices':'Factures','payments':'Paiements','balances':'Soldes clients'}[section]??'Récoltes et ventes',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if(!billingView) Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (allows('aquatic.harvest.create'))
              OutlinedButton.icon(
                onPressed: loading ? null : () => edit('HARVEST'),
                icon: const Icon(Icons.set_meal, color: Colors.green),
                label: const Text('Nouvelle récolte'),
              ),
            if (allows('aquatic.harvest.create') &&
                allows('aquatic.sales.create'))
              OutlinedButton(
                onPressed: loading ? null : () => edit('DIRECT'),
                child: const Text('Vente directe'),
              ),
            OutlinedButton(
              onPressed: () => setState(() => section = 'stock'),
              child: const Text('Stock post-récolte'),
            ),
            if (allows('aquatic.sales.create'))
              OutlinedButton(
                onPressed: loading ? null : () => edit('SALE'),
                child: const Text('Vente depuis le stock'),
              ),
            if (allows('aquatic.postharvest.loss'))
              OutlinedButton(
                onPressed: loading ? null : () => edit('LOSS'),
                child: const Text('Enregistrer une perte'),
              ),
            OutlinedButton(onPressed:()=>setState(()=>section='clients'),child:const Text('Clients')),
            OutlinedButton(
              onPressed: () => setState(() => section = 'history'),
              child: const Text('Consulter l’historique'),
            ),
            if (allows('clients.create'))
              OutlinedButton(
                onPressed: loading ? null : () => edit('CLIENT'),
                child: const Text('Nouveau client'),
              ),
          ],
        ),
        if(section=='clients' && allows('clients.create'))OutlinedButton(onPressed:loading?null:()=>edit('CLIENT'),child:const Text('Nouveau client')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            filter(
              'Installation',
              installation,
              widget.installations,
              (v) => installation = v,
            ),
            filter('Cohorte', cohort, widget.cohorts, (v) => cohort = v),
            filter('Espèce', species, widget.species, (v) => species = v),
            filter('Client', client, clients, (v) => client = v),
            filter('Statut', status, [
              {'id': 'AVAILABLE', 'name': 'Disponible'},
              {'id': 'EXHAUSTED', 'name': 'Épuisé'},
              {'id': 'CANCELED', 'name': 'Annulé'},
            ], (v) => status = v),
            OutlinedButton(onPressed: load, child: const Text('Actualiser')),
          ],
        ),
        if (section == 'history')
          OutlinedButton.icon(
            onPressed: () async {
              final p = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
                initialDateRange: DateTimeRange(start: start, end: end),
              );
              if (p != null) {
                setState(() {
                  start = p.start;
                  end = p.end;
                });
                load();
              }
            },
            icon: const Icon(Icons.calendar_month, color: Colors.green),
            label: const Text('Période de l’historique'),
          ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        if(!loading && ['invoices','payments','balances'].contains(section))...[
          if(invoices.isEmpty)const Text('Aucune facture dans ces filtres.'),
          for(final invoice in invoices)invoiceCard(invoice),
        ],
        if (!loading && section == 'clients') ...[
          if(clients.isEmpty) const Text('Aucun client.'),
          for(final customer in clients) commerceCard(context,ListTile(leading:const Icon(Icons.person_outline),title:Text('${customer['name']??customer['nom']??''}'))),
        ],
        if (!loading && section == 'stock') ...[
          if (harvests.isEmpty) const Text('Aucune récolte dans ces filtres.'),
          for (final h in harvests)
            commerceCard(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${h['species_name']} · ${h['cohort_name']} · ${h['installation_name']} · ${h['destination'] == 'DIRECT' ? 'Vente directe' : 'Stock post-récolte'}',
                  ),
                  Text(
                    '${feedWhen(h)}\nDisponible : ${h['balance']['available_quantity']} ${commerceUnit(h['stock_unit'])}\nNombre restant : ${commerceValue(h['balance']['available_count'])}\nPoids restant : ${commerceValue(h['balance']['available_mass_kg'])} kg\nConservation : ${h['storage_place']} · ${h['storage_mode']}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => details(h),
                        child: const Text('Traçabilité et factures'),
                      ),
                      if (h['balance']['status'] == 'AVAILABLE' &&
                          h['destination'] == 'STOCK' &&
                          allows('aquatic.sales.create'))
                        OutlinedButton(
                          onPressed: () => edit('SALE', row: h),
                          child: const Text('Vendre'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        if (!loading && section == 'history') ...[
          if (history.isEmpty)
            const Text('Aucun mouvement dans cette période.'),
          for (final m in history)
            commerceCard(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${m['kind'] == 'SALE'
                        ? 'Vente'
                        : m['kind'] == 'LOSS'
                        ? 'Perte post-récolte'
                        : m['kind'] == 'VOID'
                        ? 'Annulation'
                        : 'Demande de correction'} · ${feedWhen(m)}',
                  ),
                  Text(
                    '${commerceValue(m['quantity'])} ${commerceUnit(m['unit'])}\n${m['species_name'] ?? ''} · ${m['cohort_name'] ?? ''} · ${m['installation_name'] ?? ''}\n${m['reason'] ?? ''}\nAuteur : ${m['actor_name']} ${m['canceled'] == true ? '· Annulé' : ''}',
                  ),
                  if (m['invoice'] != null)
                    Text(
                      '${m['invoice']['client_name']} · ${m['invoice']['invoice_reference']}\nFacturé : ${m['invoice']['montant_total']} · Reste : ${m['invoice']['reste']}',
                    ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

class CommerceEditor extends StatefulWidget {
  const CommerceEditor({
    super.key,
    required this.service,
    required this.mode,
    required this.installations,
    required this.cohorts,
    required this.harvests,
    required this.clients,
    this.row,
    this.initialInstallation,
    this.initialCohort,
  });
  final AquaticService service;
  final String mode;
  final List<Map<String, dynamic>> installations, cohorts, harvests, clients;
  final Map<String, dynamic>? row;
  final String? initialInstallation, initialCohort;
  @override
  State<CommerceEditor> createState() => _CommerceEditorState();
}

class _CommerceEditorState extends State<CommerceEditor> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  TextEditingController c(String name) =>
      controllers.putIfAbsent(name, () => TextEditingController());
  String? installation, cohort, harvest, client, error;
  String stockUnit = 'PIECE', quality = 'UNKNOWN', destination = 'STOCK';
  DateTime at = DateTime.now();
  bool counted = false, verified = false, busy = false, uncertain = false;
  Map<String, dynamic>? review, pending;
  final originIdentity = ApiService.sessionIdentity;
  bool get isHarvest => widget.mode == 'HARVEST' || widget.mode == 'DIRECT';
  bool get isSale =>
      widget.mode == 'SALE' || (isHarvest && destination == 'DIRECT');
  bool get needsHealth => isHarvest || isSale;
  bool get isMove => widget.mode == 'SALE' || widget.mode == 'LOSS';
  Map<String, dynamic>? get selected =>
      widget.harvests.where((h) => h['id'] == harvest).firstOrNull;
  String get unit =>
      isHarvest ? stockUnit : '${selected?['stock_unit'] ?? 'KG'}';
  @override
  void initState() {
    super.initState();
    installation = widget.initialInstallation;
    cohort = widget.initialCohort;
    harvest = widget.row?['id']?.toString();
    if (widget.mode == 'DIRECT') destination = 'DIRECT';
  }

  @override
  void dispose() {
    for (final x in controllers.values) {
      x.dispose();
    }
    super.dispose();
  }

  void changed() {
    setState(() {
      review = null;
      verified = false;
    });
  }

  String decimal(String key) => c(key).text.trim().replaceAll(',', '.');
  String? validateNumber(
    String? v, {
    bool integer = false,
    bool zero = false,
    bool optional = false,
    int places = 6,
  }) {
    if (optional && (v == null || v.trim().isEmpty)) return null;
    final text = v?.trim().replaceAll(',', '.') ?? '';
    if (text.contains('.') && text.split('.').last.length > places) {
      return 'Au maximum $places décimales.';
    }
    if (!(integer ? RegExp(r'^\d+$') : RegExp(r'^\d+(\.\d{1,6})?$')).hasMatch(
      text,
    )) {
      return 'Renseignez une mesure valide.';
    }
    final n = num.tryParse(text);
    return n == null || (zero ? n < 0 : n <= 0) ? 'Quantité invalide.' : null;
  }

  Widget field(
    String key,
    String label, {
    bool required = true,
    bool number = false,
    bool integer = false,
    bool optional = false,
    bool money = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: c(key),
      decoration: InputDecoration(labelText: label),
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) {
        if (money || key == 'quantity' || key == 'mass' || key == 'count') {
          setState(() {});
        }
      },
      validator: (v) => number
          ? validateNumber(
              v,
              integer: integer,
              zero: money || key == 'secondary_count',
              optional: optional,
              places: money || key == 'amount' ? 2 : 6,
            )
          : (required && (v == null || v.trim().isEmpty)
                ? 'Champ requis.'
                : null),
    ),
  );
  Widget dropdown(
    String label,
    String? value,
    List<Map<String, dynamic>> rows,
    ValueChanged<String?> change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: rows.any((r) => '${r['id']}' == value) ? value : null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final r in rows)
          DropdownMenuItem(
            value: '${r['id']}',
            child: Text(
              '${r['name'] ?? r['nom']}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: change,
      validator: (v) => v == null ? 'Choisissez une référence.' : null,
    ),
  );
  Future<void> precautions() async {
    if (originIdentity != ApiService.sessionIdentity) return;
    if ((isHarvest && (installation == null || cohort == null)) ||
        (!isHarvest && harvest == null)) {
      setState(() => error = 'Choisissez d’abord l’origine.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      review = null;
      verified = false;
    });
    try {
      final result = await widget.service.read(
        'commerce-check/?${Uri(queryParameters: {'as_of': at.toUtc().toIso8601String(), if (isHarvest) 'installation': installation!, if (isHarvest) 'cohort': cohort!, if (!isHarvest) 'harvest': harvest!}).query}',
      );
      if (!mounted || originIdentity != ApiService.sessionIdentity) return;
      setState(() => review = result);
    } catch (e) {
      if (mounted && originIdentity == ApiService.sessionIdentity) {
        setState(() => error = commerceError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Map<String, dynamic> body() {
    final d = <String, dynamic>{
      'occurred_at': at.toUtc().toIso8601String(),
      'note': c('note').text.trim(),
    };
    final price = isSale
        ? {'client': int.parse(client!), 'unit_price': decimal('price')}
        : <String, dynamic>{};
    if (widget.mode == 'CLIENT') {
      return {
        ...d,
        'customer': {
          'nom': c('name').text.trim(),
          'telephone': c('phone').text.trim(),
          'pays': c('country').text.trim(),
          'ville': c('town').text.trim(),
        },
      };
    }
    if (widget.mode == 'PAYMENT') {
      return {...d, 'sale': widget.row!['id'], 'amount': decimal('amount')};
    }
    if (widget.mode == 'VOID' || widget.mode == 'CORRECTION') {
      return {
        ...d,
        'harvest': widget.row!['id'],
        'target': widget.row!['target'],
        'reason': c('reason').text.trim(),
      };
    }
    final health = {
      'health_token': review?['health_token'],
      'human_verified': verified,
      'verification_reason': c('verification').text.trim(),
    };
    if (isHarvest) {
      return {
        ...d,
        'installation': installation,
        'cohort': cohort,
        'live_count': int.parse(c('count').text),
        'counted': counted,
        'mass_kg': quality == 'UNKNOWN' ? null : decimal('mass'),
        'mass_quality': quality,
        'stock_unit': stockUnit,
        'destination': destination,
        'storage_place': c('place').text.trim(),
        'storage_mode': c('storage').text.trim(),
        'conservation_note': c('conservation').text.trim(),
        'review': health,
        if (isSale) 'direct_sale': price,
      };
    }
    return {
      ...d,
      'harvest': harvest,
      'quantity': decimal('quantity'),
      'count': unit == 'PIECE'
          ? int.parse(decimal('quantity'))
          : c('secondary_count').text.trim().isEmpty
          ? null
          : int.parse(c('secondary_count').text.trim()),
      'mass_kg': unit == 'KG'
          ? decimal('quantity')
          : c('secondary_mass').text.trim().isEmpty
          ? null
          : decimal('secondary_mass'),
      if (isSale) 'price': price,
      if (isSale) 'review': health,
      if (widget.mode == 'LOSS') 'reason': c('reason').text.trim(),
    };
  }

  String get path => isHarvest
      ? 'harvests/'
      : const {
          'CLIENT': 'commerce-clients/',
          'PAYMENT': 'commerce-payments/',
          'SALE': 'harvest-sales/',
          'LOSS': 'postharvest-losses/',
          'VOID': 'commerce-cancellations/',
          'CORRECTION': 'commerce-corrections/',
        }[widget.mode]!;
  Future<void> save() async {
    if (originIdentity != ApiService.sessionIdentity) {
      setState(
        () => error = 'Session modifiée. Fermez et ouvrez une nouvelle saisie.',
      );
      return;
    }
    if (!uncertain) {
      if (!form.currentState!.validate()) return;
      if (isHarvest && !counted) {
        setState(
          () => error =
              'Confirmez le nombre réellement compté, sans conversion depuis le poids.',
        );
        return;
      }
      if (needsHealth &&
          (review == null || !verified || review!['blocked'] == true)) {
        setState(
          () => error =
              'Relisez et vérifiez les précautions sanitaires avant de confirmer.',
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
      if (!mounted || originIdentity != ApiService.sessionIdentity) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted || originIdentity != ApiService.sessionIdentity) return;
      final known =
          e is ApiHttpException &&
          e.status >= 400 &&
          e.status < 500 &&
          e.status != 408;
      setState(() {
        busy = false;
        uncertain = !known;
        if (known) {
          pending = null;
          if ('$e'.contains('HEALTH_REVIEW_STALE')) {
            review = null;
            verified = false;
          }
        }
        error = known
            ? commerceError(e)
            : 'Réponse non reçue. Réessayez cette même opération pour éviter tout doublon.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = const {
      'HARVEST': 'Enregistrer une récolte',
      'DIRECT': 'Récolte et vente directe',
      'SALE': 'Vente depuis le stock',
      'LOSS': 'Perte post-récolte',
      'CLIENT': 'Nouveau client',
      'PAYMENT': 'Enregistrer un paiement',
      'VOID': 'Annulation motivée',
      'CORRECTION': 'Demande de correction financière',
    }[widget.mode]!;
    final available = widget.harvests
        .where(
          (h) =>
              h['destination'] == 'STOCK' &&
              h['balance']['status'] == 'AVAILABLE',
        )
        .map(
          (h) => {
            ...h,
            'name':
                '${h['species_name']} · ${h['cohort_name']} · ${feedWhen(h)}',
          },
        )
        .toList();
    final total = commerceTotal(
      isHarvest
          ? (unit == 'KG' ? decimal('mass') : c('count').text)
          : decimal('quantity'),
      decimal('price'),
    );
    return Theme(
      data: designSystemV2(Theme.of(context)),
      child: V2AlertDialog(
        backgroundColor: V2Colors.background,
        title: Text(title),
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
                    if (widget.mode == 'CLIENT') ...[
                      field('name', 'Nom du client'),
                      field('phone', 'Téléphone (facultatif)', required: false),
                      field(
                        'country',
                        'Code pays (facultatif)',
                        required: false,
                      ),
                      field('town', 'Ville (facultatif)', required: false),
                    ],
                    if (isHarvest) ...[
                      const Text(
                        'Le nombre confirmé débite le vivant. Aucun nombre de poissons n’est déduit des kilogrammes.',
                      ),
                      dropdown(
                        'Installation d’origine',
                        installation,
                        widget.installations,
                        (v) {
                          installation = v;
                          changed();
                        },
                      ),
                      dropdown('Cohorte d’origine', cohort, widget.cohorts, (
                        v,
                      ) {
                        cohort = v;
                        changed();
                      }),
                      if (cohort != null)
                        Text(
                          'Espèce : ${widget.cohorts.where((x) => x['id'] == cohort).firstOrNull?['species_name'] ?? 'issue de la cohorte'}',
                        ),
                      field(
                        'count',
                        'Poissons réellement comptés',
                        number: true,
                        integer: true,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: counted,
                        onChanged: (v) => setState(() => counted = v ?? false),
                        title: const Text(
                          'Je confirme le nombre réellement compté et récolté',
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: quality,
                        decoration: const InputDecoration(
                          labelText: 'Qualité du poids',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'UNKNOWN',
                            child: Text('Non renseigné'),
                          ),
                          DropdownMenuItem(
                            value: 'MEASURED',
                            child: Text('Mesuré'),
                          ),
                          DropdownMenuItem(
                            value: 'ESTIMATED',
                            child: Text('Estimé'),
                          ),
                        ],
                        onChanged: (v) => setState(() => quality = v!),
                      ),
                      if (quality != 'UNKNOWN')
                        field('mass', 'Poids total (kg)', number: true),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: stockUnit,
                        decoration: const InputDecoration(
                          labelText: 'Unité de suivi et de prix',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'KG',
                            child: Text('Kilogrammes mesurés (kg)'),
                          ),
                          DropdownMenuItem(
                            value: 'PIECE',
                            child: Text('Nombre de poissons'),
                          ),
                        ],
                        onChanged: (v) => setState(() => stockUnit = v!),
                      ),
                      if (stockUnit == 'KG' && quality != 'MEASURED')
                        const Text(
                          'Un poids réellement mesuré est requis pour suivre le stock en kg.',
                          style: TextStyle(color: Colors.red),
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: destination,
                        decoration: const InputDecoration(
                          labelText: 'Destination',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'STOCK',
                            child: Text('Stock post-récolte'),
                          ),
                          DropdownMenuItem(
                            value: 'DIRECT',
                            child: Text('Vente directe'),
                          ),
                        ],
                        onChanged: (v) => setState(() => destination = v!),
                      ),
                      if (destination == 'STOCK') ...[
                        field('place', 'Lieu de conservation'),
                        field('storage', 'Mode de conservation'),
                        field(
                          'conservation',
                          'Date ou information de conservation (facultatif)',
                          required: false,
                        ),
                      ],
                    ],
                    if (isMove) ...[
                      dropdown('Récolte en stock', harvest, available, (v) {
                        harvest = v;
                        changed();
                      }),
                      if (selected != null)
                        Text(
                          'Disponible : ${selected!['balance']['available_quantity']} ${commerceUnit(unit)}\nNombre : ${commerceValue(selected!['balance']['available_count'])}\nPoids : ${commerceValue(selected!['balance']['available_mass_kg'])} kg',
                        ),
                      field(
                        'quantity',
                        'Quantité (${commerceUnit(unit)})',
                        number: true,
                        integer: unit == 'PIECE',
                      ),
                      if (unit == 'KG')
                        const Text(
                          'Le nombre de poissons n’est pas déduit du poids. Sans comptage secondaire, son solde devient non renseigné.',
                        ),
                    ],
                    if (isMove)
                      ExpansionTile(
                        maintainState: true,
                        title: const Text('Mesure secondaire (facultative)'),
                        children: [
                          if (unit == 'KG')
                            field(
                              'secondary_count',
                              'Poissons réellement comptés (facultatif)',
                              number: true,
                              integer: true,
                              optional: true,
                            )
                          else
                            field(
                              'secondary_mass',
                              'Poids réellement mesuré (kg, facultatif)',
                              number: true,
                              optional: true,
                            ),
                        ],
                      ),
                    if (widget.mode == 'VOID' || widget.mode == 'CORRECTION')
                      Text(
                        '${widget.row?['cohort_name'] ?? 'Récolte'} · ${widget.row?['installation_name'] ?? ''}\n${widget.row?['occurred_at'] == null ? '' : feedWhen(widget.row!)}\n${widget.row?['invoice_reference'] ?? (widget.row?['target'] == null ? 'Récolte sans suite' : 'Mouvement de cette récolte')}',
                      ),
                    if (isSale) ...[
                      dropdown(
                        'Client',
                        client,
                        widget.clients,
                        (v) => setState(() => client = v),
                      ),
                      field(
                        'price',
                        'Prix par ${unit == 'KG' ? 'kg' : 'poisson'} (${AppSettings.instance.currencyCode})',
                        number: true,
                        money: true,
                      ),
                      Text(
                        'Montant total : ${total ?? 'Non renseigné'} ${AppSettings.instance.currencyCode}',
                      ),
                    ],
                    if (widget.mode == 'PAYMENT') ...[
                      Text(
                        '${widget.row!['invoice_reference']} · ${widget.row!['client_name']}\nReste : ${widget.row!['reste']}',
                      ),
                      field('amount', 'Montant du paiement', number: true),
                    ],
                    if (widget.mode == 'LOSS' ||
                        widget.mode == 'VOID' ||
                        widget.mode == 'CORRECTION')
                      field('reason', 'Motif'),
                    if (widget.mode == 'CORRECTION')
                      const Text(
                        'La demande conserve le motif. Aucun avoir, remboursement, effacement de facture ou changement de créance n’est automatique.',
                      ),
                    if (widget.mode != 'CLIENT')
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: at,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (d != null) {
                                at = DateTime(
                                  d.year,
                                  d.month,
                                  d.day,
                                  at.hour,
                                  at.minute,
                                  at.second,
                                  at.millisecond,
                                );
                                changed();
                              }
                            },
                            icon: const Icon(
                              Icons.calendar_month,
                              color: Colors.green,
                            ),
                            label: Text(
                              'Date : ${at.day}/${at.month}/${at.year}',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(at),
                              );
                              if (t != null) {
                                at = DateTime(
                                  at.year,
                                  at.month,
                                  at.day,
                                  t.hour,
                                  t.minute,
                                );
                                changed();
                              }
                            },
                            child: Text(
                              'Heure : ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ],
                      ),
                    if (widget.mode != 'CLIENT')
                      field('note', 'Note (facultative)', required: false),
                    if (needsHealth) ...[
                      OutlinedButton.icon(
                        onPressed: precautions,
                        icon: const Icon(
                          Icons.health_and_safety,
                          color: Colors.green,
                        ),
                        label: const Text(
                          'Vérifier les précautions sanitaires',
                        ),
                      ),
                      if (review != null) ...[
                        Text('${review!['notice']}'),
                        if ((review!['matches'] as List? ?? []).isEmpty)
                          const Text(
                            'Aucun traitement enregistré trouvé. Cela ne constitue pas une autorisation de vente.',
                          ),
                        for (final m in review!['matches'] as List? ?? [])
                          Text(
                            'Traitement : ${m['treatment']?['product_name'] ?? 'Non renseigné'}\nDate : ${m['treatment'] == null ? 'Non renseignée' : feedWhen(m['treatment'] as Map)}\nQuantité administrée : ${m['treatment']?['quantity'] ?? 'Non renseignée'} ${m['treatment']?['unit'] ?? ''}\n${m['precaution']['message']}\nSource : ${m['precaution']['source'] ?? 'Non renseignée'}\nFin documentée : ${m['precaution']['until'] ?? 'Non renseignée'}\n${m['scope_match'] == 'RECORDED_SCOPE' ? 'Population enregistrée' : 'Traçabilité à vérifier après changement de contexte'}',
                          ),
                        if (review!['blocked'] == true)
                          const Text(
                            'Confirmation bloquée : traitement en cours ou délai documenté actif.',
                            style: TextStyle(color: Colors.red),
                          ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: verified,
                          onChanged: review!['blocked'] == true
                              ? null
                              : (v) => setState(() => verified = v ?? false),
                          title: const Text(
                            'J’ai vérifié les informations et sources applicables à cette population',
                          ),
                        ),
                        field(
                          'verification',
                          'Justification de la vérification humaine',
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
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
              busy
                  ? 'Enregistrement…'
                  : uncertain
                  ? 'Réessayer la même opération'
                  : 'Enregistrer',
            ),
          ),
        ],
      ),
    );
  }
}
