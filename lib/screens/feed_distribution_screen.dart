import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/terre_et_or_theme.dart';

String _feedDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _feedTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

double _feedKg(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _formatKg(double value) {
  final formatted = value.toStringAsFixed(3);
  return formatted.replaceFirst(RegExp(r'\.?0+$'), '');
}

class FeedDistributionScreen extends StatefulWidget {
  final ApiService apiService;
  final int lotId;
  final String lotName;

  const FeedDistributionScreen({
    super.key,
    required this.apiService,
    required this.lotId,
    required this.lotName,
  });

  @override
  State<FeedDistributionScreen> createState() => _FeedDistributionScreenState();
}

class _FeedDistributionScreenState extends State<FeedDistributionScreen> {
  List<dynamic> distributions = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.apiService.getFeedDistributions(widget.lotId);
      if (!mounted) return;
      setState(() {
        distributions = result;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = context.tr('feed_load_error');
      });
    }
  }

  DateTime _entryDate(dynamic entry) {
    final stamp = DateTime.tryParse('${entry['distribution_at'] ?? ''}');
    if (stamp != null) return stamp.toLocal();
    return DateTime.tryParse('${entry['date'] ?? ''}') ?? DateTime(1970);
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FeedDistributionFormScreen(
          apiService: widget.apiService,
          lotId: widget.lotId,
          lotName: widget.lotName,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<dynamic>>{};
    for (final entry in distributions) {
      final key = _feedDate(_entryDate(entry));
      groups.putIfAbsent(key, () => []).add(entry);
    }

    return Theme(
      data: terreEtOrTheme(context),
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('feed_tracking'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: const Key('feedHistory'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  TerreEtOrHeader(
                    icon: Icons.grass_outlined,
                    title: context.tr('feed_tracking'),
                    subtitle: widget.lotName,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const Key('addFeedDistribution'),
                      onPressed: _add,
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('add_feed_distribution')),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else if (error != null) ...[
                    Text(error!, key: const Key('feedHistoryError')),
                    TextButton(
                      onPressed: _load,
                      child: Text(context.tr('refresh')),
                    ),
                  ] else if (distributions.isEmpty)
                    TerreEtOrPanel(child: Text(context.tr('feed_empty')))
                  else
                    for (final group in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          group.key,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TerreEtOrPanel(
                        child: Column(
                          children: [
                            for (final entry in group.value)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.grass_outlined),
                                title: Text('${entry['aliment'] ?? ''}'),
                                subtitle: Text(
                                  entry['distribution_at'] == null
                                      ? context.tr('feed_time_unknown')
                                      : _feedTime(_entryDate(entry)),
                                ),
                                trailing: Text(
                                  '${_formatKg(_feedKg(entry['quantite_kg']))} kg',
                                ),
                              ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(context.tr('feed_daily_total')),
                                Text(
                                  '${_formatKg(group.value.fold<double>(0, (sum, entry) => sum + _feedKg(entry['quantite_kg'])))} kg',
                                  key: const Key('feedDailyTotal'),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FeedDistributionFormScreen extends StatefulWidget {
  final ApiService apiService;
  final int lotId;
  final String lotName;

  const FeedDistributionFormScreen({
    super.key,
    required this.apiService,
    required this.lotId,
    required this.lotName,
  });

  @override
  State<FeedDistributionFormScreen> createState() =>
      _FeedDistributionFormScreenState();
}

class _FeedDistributionFormScreenState extends State<FeedDistributionFormScreen> {
  final formKey = GlobalKey<FormState>();
  final feedName = TextEditingController();
  final quantity = TextEditingController();
  final note = TextEditingController();
  final price = TextEditingController();
  List<dynamic> expenses = [];
  int? selectedExpenseId;
  DateTime dateTime = DateTime.now();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    try {
      final detail = await widget.apiService.getLotDetail(widget.lotId);
      if (!mounted) return;
      setState(() => expenses = detail['depenses'] as List<dynamic>? ?? []);
    } catch (_) {
      // Le lien avec une dépense est facultatif ; la distribution reste possible.
    }
  }

  @override
  void dispose() {
    feedName.dispose();
    quantity.dispose();
    note.dispose();
    price.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: dateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() => dateTime = DateTime(
          selected.year, selected.month, selected.day,
          dateTime.hour, dateTime.minute,
        ));
  }

  Future<void> _selectTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dateTime),
    );
    if (selected == null || !mounted) return;
    setState(() => dateTime = DateTime(
          dateTime.year, dateTime.month, dateTime.day,
          selected.hour, selected.minute,
        ));
  }

  Future<void> _save() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.apiService.createFeedDistribution(
        lotId: widget.lotId,
        distributedAt: dateTime,
        feedName: feedName.text.trim(),
        quantityKg: double.parse(quantity.text.trim().replaceAll(',', '.')),
        pricePerKg: price.text.trim().isEmpty
            ? null
            : double.parse(price.text.trim().replaceAll(',', '.')),
        expenseId: selectedExpenseId,
        note: note.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('feed_save_error'))),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: terreEtOrTheme(context),
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('add_feed_distribution'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TerreEtOrHeader(
                    icon: Icons.grass_outlined,
                    title: context.tr('add_feed_distribution'),
                    subtitle: widget.lotName,
                  ),
                  OutlinedButton.icon(
                    key: const Key('feedDatePicker'),
                    onPressed: _selectDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('${context.tr('feed_date')} : ${_feedDate(dateTime)}'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('feedTimePicker'),
                    onPressed: _selectTime,
                    icon: const Icon(Icons.access_time),
                    label: Text('${context.tr('feed_time')} : ${_feedTime(dateTime)}'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('feedNameField'),
                    controller: feedName,
                    maxLength: 120,
                    decoration: InputDecoration(labelText: context.tr('feed_name')),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? context.tr('feed_invalid_name')
                        : null,
                  ),
                  TextFormField(
                    key: const Key('feedQuantityField'),
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: context.tr('feed_quantity')),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
                      return parsed == null || !parsed.isFinite || parsed <= 0
                          ? context.tr('feed_invalid_quantity')
                          : null;
                    },
                  ),
                  TextFormField(
                    key: const Key('feedNoteField'),
                    controller: note,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: context.tr('feed_note')),
                  ),
                  ExpansionTile(
                    title: Text(context.tr('feed_cost_optional')),
                    children: [
                      Text(context.tr('feed_cost_hint')),
                      if (expenses.isNotEmpty)
                        DropdownButtonFormField<int>(
                          key: const Key('feedExpenseDropdown'),
                          isExpanded: true,
                          initialValue: selectedExpenseId ?? 0,
                          decoration: InputDecoration(
                            labelText: context.tr('feed_existing_expense'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 0,
                              child: Text(context.tr('feed_no_expense')),
                            ),
                            for (final expense in expenses)
                              DropdownMenuItem(
                                value: expense['id'] as int,
                                child: Text('#${expense['id']} · ${expense['montant']}'),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => selectedExpenseId = value == 0 ? null : value,
                          ),
                        ),
                      TextFormField(
                        key: const Key('feedPriceField'),
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: context.tr('feed_price_kg')),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final amount = double.tryParse(value.trim().replaceAll(',', '.'));
                          return amount == null || !amount.isFinite || amount < 0
                              ? context.tr('feed_invalid_price')
                              : null;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    key: const Key('saveFeedDistribution'),
                    onPressed: saving ? null : _save,
                    child: Text(context.tr('save')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
