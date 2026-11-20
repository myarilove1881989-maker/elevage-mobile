import 'package:flutter/material.dart';
import '../widgets/v2_components.dart';
import '../widgets/detail_widgets.dart';
import '../theme/terre_et_or_theme.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/invoice_pdf_service.dart';
import 'aquatic_service.dart';
import 'commerce_panel.dart';

BigInt aquaticCents(dynamic value) {
  final s = '$value';
  if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(s))
    throw const FormatException('INVALID_MONEY');
  final negative = s.startsWith('-'), p = s.replaceFirst('-', '').split('.');
  final n =
      BigInt.parse(p[0]) * BigInt.from(100) +
      BigInt.parse((p.length == 1 ? '' : p[1]).padRight(2, '0'));
  return negative ? -n : n;
}

String aquaticMoney(BigInt cents) {
  final settings = AppSettings.instance, absolute = cents.abs();
  final english = settings.languageCode == 'en';
  final integer = (absolute ~/ BigInt.from(100)).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => english ? ',' : '\u202f',
  );
  final fraction = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
  final value =
      '${cents.isNegative ? '-' : ''}$integer${fraction == '00' ? '' : '${english ? '.' : ','}$fraction'}';
  return settings.currencyCode == 'XAF'
      ? '$value ${settings.currency.symbol}'
      : '${settings.currency.symbol}$value';
}

class AquaticClientsScreen extends StatefulWidget {
  const AquaticClientsScreen({
    super.key,
    required this.service,
    required this.filters,
    required this.canPay,
    this.includeAllClients = false,
    this.canCreate = false,
  });
  final AquaticService service;
  final Map<String, String> filters;
  final bool canPay, includeAllClients, canCreate;
  @override
  State<AquaticClientsScreen> createState() => _AquaticClientsScreenState();
}

class _AquaticClientsScreenState extends State<AquaticClientsScreen> {
  List<Map<String, dynamic>> invoices = [];
  List<Map<String, dynamic>> catalog = [];
  bool loading = true;
  String? error;
  String search = '', status = 'Tous';
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    epoch++;
    super.dispose();
  }

  Future<void> load() async {
    final n = ++epoch, identity = ApiService.sessionIdentity;
    setState(() {
      loading = true;
      error = null;
      invoices = [];
    });
    try {
      final rows = await widget.service.list(
        'finance-client-ledger/?${Uri(queryParameters: widget.filters).query}',
      );
      if (!mounted || n != epoch || identity != ApiService.sessionIdentity)
        return;
      final customers = widget.includeAllClients
          ? await widget.service.list('commerce-clients/')
          : <Map<String, dynamic>>[];
      if (!mounted || n != epoch || identity != ApiService.sessionIdentity)
        return;
      // Validate the decimal projection before showing any totals.
      for (final r in rows) {
        aquaticCents(r['amount']);
        aquaticCents(r['paid_as_of']);
        aquaticCents(r['balance_as_of']);
      }
      setState(() {
        invoices = rows;
        catalog = customers;
        loading = false;
      });
    } catch (_) {
      if (mounted && n == epoch && identity == ApiService.sessionIdentity)
        setState(() {
          loading = false;
          error = 'Lecture impossible. Réessayez.';
        });
    }
  }

  BigInt sum(Iterable<Map<String, dynamic>> rows, String key) =>
      rows.fold(BigInt.zero, (a, r) => a + aquaticCents(r[key]));
  String state(BigInt paid, BigInt due) => due <= BigInt.zero
      ? 'Payés'
      : paid > BigInt.zero
      ? 'Partiels'
      : 'Impayés';
  Future<void> pay(Map<String, dynamic> invoice) async {
    final identity = ApiService.sessionIdentity;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => CommerceEditor(
        service: widget.service,
        mode: 'PAYMENT',
        installations: const [],
        cohorts: const [],
        harvests: const [],
        clients: const [],
        row: {
          'id': invoice['sale_id'],
          'invoice_reference': 'FAC-${invoice['sale_id']}',
          'client_name': invoice['client_name'],
          'reste': invoice['balance_as_of'],
        },
      ),
    );
    if (changed == true && mounted && identity == ApiService.sessionIdentity)
      await load();
  }

  Future<void> createClient() async {
    final identity = ApiService.sessionIdentity;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => CommerceEditor(
        service: widget.service,
        mode: 'CLIENT',
        installations: const [],
        cohorts: const [],
        harvests: const [],
        clients: catalog,
      ),
    );
    if (changed == true && mounted && identity == ApiService.sessionIdentity)
      await load();
  }

  Widget metrics(List<Map<String, dynamic>> rows) => LayoutBuilder(
    builder: (context, c) => GridView.count(
      crossAxisCount: c.maxWidth < 600 ? 1 : 3,
      childAspectRatio: c.maxWidth < 600 ? 3 : 1.45,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        DetailMetricCard(
          label: 'Total facturé',
          value: aquaticMoney(sum(rows, 'amount')),
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFF3D7FA1),
        ),
        DetailMetricCard(
          label: 'Total payé',
          value: aquaticMoney(sum(rows, 'paid_as_of')),
          icon: Icons.check_circle_outline,
          color: TerreEtOrColors.green,
        ),
        DetailMetricCard(
          label: 'Solde à recevoir',
          value: aquaticMoney(sum(rows, 'balance_as_of')),
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFFD85B4B),
        ),
      ],
    ),
  );

  Future<void> customer(List<Map<String, dynamic>> rows) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => V2Scaffold(
          appBar: V2AppBar(title: Text('${rows.first['client_name']}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('${rows.first['client_phone']}'),
              const SizedBox(height: 14),
              metrics(rows),
              const SizedBox(height: 14),
              for (final row in rows.where((r) => r['sale_id'] != null))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FAC-${row['sale_id']} · ${row['date']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Facturé : ${aquaticMoney(aquaticCents(row['amount']))}',
                        ),
                        Text(
                          'Payé : ${aquaticMoney(aquaticCents(row['paid_as_of']))}',
                        ),
                        Text(
                          'Restant : ${aquaticMoney(aquaticCents(row['balance_as_of']))}',
                        ),
                        for (final payment in row['payments'] as List)
                          Text(
                            '${payment['date']} · ${payment['amount']} ${AppSettings.instance.currencyCode}',
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () async {
                                final identity = ApiService.sessionIdentity;
                                try {
                                  final invoice = await widget.service.read(
                                    'commerce-invoices/${row['sale_id']}/',
                                  );
                                  if (!mounted ||
                                      identity != ApiService.sessionIdentity)
                                    return;
                                  await InvoicePdfService.openInvoice(
                                    sale: invoice,
                                    customerName: '${row['client_name']}',
                                    customerPhone: '${row['client_phone']}',
                                    languageCode:
                                        AppSettings.instance.languageCode,
                                  );
                                } catch (_) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Facture indisponible.'),
                                      ),
                                    );
                                }
                              },
                              child: const Text('Facture'),
                            ),
                            if (widget.canPay &&
                                aquaticCents(row['balance_as_of']) >
                                    BigInt.zero)
                              OutlinedButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await pay(row);
                                },
                                child: const Text('Enregistrer un paiement'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in invoices) {
      groups.putIfAbsent('${r['client']}', () => []).add(r);
    }
    for (final c in catalog) {
      groups.putIfAbsent(
        '${c['id']}',
        () => [
          {
            'client': c['id'],
            'client_name': c['nom'],
            'client_phone': c['telephone'] ?? '',
            'sale_id': null,
            'amount': '0.00',
            'paid_as_of': '0.00',
            'balance_as_of': '0.00',
            'payments': [],
          },
        ],
      );
    }
    final visible =
        groups.values.where((rows) {
          final r = rows.first;
          final paid = sum(rows, 'paid_as_of'),
              due = sum(rows, 'balance_as_of');
          return ('${r['client_name']} ${r['client_phone']}')
                  .toLowerCase()
                  .contains(search.toLowerCase()) &&
              (status == 'Tous' || state(paid, due) == status);
        }).toList()..sort((a, b) {
          final order = sum(
            b,
            'balance_as_of',
          ).compareTo(sum(a, 'balance_as_of'));
          return order != 0
              ? order
              : '${a.first['client_name']}'.compareTo(
                  '${b.first['client_name']}',
                );
        });
    return V2Scaffold(
      appBar: V2AppBar(
        title: Text(widget.includeAllClients ? 'Clients' : 'Dettes clients'),
        actions: [
          if (widget.canCreate)
            IconButton(
              tooltip: 'Nouveau client',
              onPressed: loading ? null : createClient,
              icon: const Icon(Icons.person_add_alt),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: TextButton(onPressed: load, child: Text(error!)),
            )
          : RefreshIndicator(
              onRefresh: load,
              child: LayoutBuilder(
                builder: (context, c) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    metrics(invoices),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: V2InputDecoration(
                        hintText: 'Rechercher par nom ou téléphone',
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (v) => setState(() => search = v),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in [
                          'Tous',
                          'Payés',
                          'Partiels',
                          'Impayés',
                        ])
                          ChoiceChip(
                            label: Text(s),
                            selected: status == s,
                            selectedColor: TerreEtOrColors.paleGold,
                            onSelected: (_) => setState(() => status = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final rows in visible) clientCard(rows),
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Aucun client.'),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget clientCard(List<Map<String, dynamic>> rows) {
    final paid = sum(rows, 'paid_as_of'), due = sum(rows, 'balance_as_of');
    final status = due <= BigInt.zero
        ? 'PAYE'
        : paid > BigInt.zero
        ? 'PARTIEL'
        : 'IMPAYE';
    final statusColor = status == 'PAYE'
        ? TerreEtOrColors.green
        : status == 'PARTIEL'
        ? TerreEtOrColors.gold
        : const Color(0xFFD85B4B);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => customer(rows),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final identity = Row(
                children: [
                  CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: .13),
                    child: Icon(Icons.person_outline, color: statusColor),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${rows.first['client_name']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if ('${rows.first['client_phone']}'.isNotEmpty)
                          Text(
                            '${rows.first['client_phone']}',
                            style: const TextStyle(
                              color: TerreEtOrColors.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
              final badge = Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              );
              final amounts = Row(
                children: [
                  Expanded(
                    child: _amount(
                      'Facturé',
                      sum(rows, 'amount'),
                      const Color(0xFF3D7FA1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _amount(
                      'Payé',
                      sum(rows, 'paid_as_of'),
                      TerreEtOrColors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _amount(
                      'Reste',
                      sum(rows, 'balance_as_of'),
                      statusColor,
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 12),
                        badge,
                      ],
                    ),
                    const SizedBox(height: 12),
                    amounts,
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 230, child: identity),
                  const SizedBox(width: 16),
                  Expanded(child: amounts),
                  const SizedBox(width: 12),
                  badge,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _amount(String label, BigInt value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: TerreEtOrColors.muted, fontSize: 11),
      ),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          aquaticMoney(value),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    ],
  );
}
