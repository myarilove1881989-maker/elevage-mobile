import '../services/money_input.dart';
import '../widgets/v2_components.dart';
import '../widgets/mutation_refresh.dart';
import 'package:flutter/material.dart';
import '../widgets/feed_distribution_fields.dart';
import '../offline/outbox.dart' show newOperationUuid;

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/terrain_entry_gate.dart';

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

class _FeedDistributionScreenState extends State<FeedDistributionScreen> with MutationRefresh<FeedDistributionScreen> {
  @override
  Future<void> refreshAfterMutation() async { await _load(); }
  List<dynamic> distributions = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> correctDistribution(Map entry,bool cancel) async {
    final physical=entry['physical_stock'] as Map;
    final amount=TextEditingController(text:'${entry['quantite_kg']}'),reason=TextEditingController();
    Map<String,dynamic>? pending;
    await showDialog<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update)=>V2AlertDialog(
      title:Text(cancel?'Annuler la distribution':'Corriger la quantité'),content:Column(mainAxisSize:MainAxisSize.min,children:[
        if(!cancel)V2Field(child:TextField(controller:amount,enabled:pending==null,decoration:const V2InputDecoration(labelText:'Nouvelle quantité totale (kg)',))),
        V2Field(child:TextField(controller:reason,enabled:pending==null,decoration:const V2InputDecoration(labelText:'Motif obligatoire',)))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Fermer')),
        TextButton(onPressed:()async{
          if(reason.text.trim().length<3)return;
          pending??={'operation_uuid':newOperationUuid(),'expected_version':physical['distribution_version'],'reason':reason.text.trim(),if(cancel)'confirm':true,if(!cancel)'quantite_kg':amount.text.trim().replaceAll(',','.')};
          try {
            if(cancel)await widget.apiService.deleteForMaintenance('/alimentation/distributions/${entry['id']}/',pending!);
            else await widget.apiService.patch('/alimentation/distributions/${entry['id']}/',pending!);
            if(dialog.mounted)Navigator.pop(dialog);if(mounted)await _load();
          } catch(_){if(dialog.mounted)update((){});if(mounted)ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content:Text('Résultat à vérifier : renvoyer conservera la même opération.')));}
        },child:const Text('Confirmer'))])));
    amount.dispose();reason.dispose();
  }
  Future<void> _load() async {
    markDataFresh();
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
      child: V2Scaffold(
        appBar: V2AppBar(title: Text(context.tr('feed_tracking'))),
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
                    child: BusinessCommand(api: widget.apiService, actions: const {'feed.create'}, child: ElevatedButton.icon(
                      key: const Key('addFeedDistribution'),
                      onPressed: _add,
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('add_feed_distribution')),
                    )),
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
                                leading: entry['id'] is int && entry['local_only']!=true && entry['physical_stock'] is Map && entry['physical_stock']['distribution_version'] is String
                                  ? BusinessCommand(api:widget.apiService,actions:const {'feed.update','feed.delete'},child:PopupMenuButton<bool>(
                                    onSelected:(cancel)=>correctDistribution(Map<String,dynamic>.from(entry as Map),cancel),
                                    itemBuilder:(_)=>const [PopupMenuItem(value:false,child:Text('Corriger la quantité')),PopupMenuItem(value:true,child:Text('Annuler avec motif'))]))
                                  : const Icon(Icons.grass_outlined),
                                title: Text('${entry['aliment'] ?? ''}${entry['local_only']==true?' - en attente':''}${entry['_review_required']==true?' - à examiner':''}'),
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

class FeedDistributionFormScreen extends StatelessWidget {
  const FeedDistributionFormScreen({super.key,required this.apiService,required this.lotId,required this.lotName});
  final ApiService apiService;
  final int lotId;
  final String lotName;
  @override
  Widget build(BuildContext context)=>TerrainEntryGate(api:apiService,actions:const {'feed.create'},
    builder:(_)=>_ClassicFeedDistributionForm(apiService:apiService,lotId:lotId,lotName:lotName));
}

class _ClassicFeedDistributionForm extends StatefulWidget {
  final ApiService apiService;
  final int lotId;
  final String lotName;

  const _ClassicFeedDistributionForm({
    required this.apiService,
    required this.lotId,
    required this.lotName,
  });

  @override
  State<_ClassicFeedDistributionForm> createState() =>
      _FeedDistributionFormScreenState();
}

class _FeedDistributionFormScreenState extends State<_ClassicFeedDistributionForm> {
  final formKey = GlobalKey<FormState>();
  final feedName = TextEditingController();
  final quantity = TextEditingController();
  final note = TextEditingController();
  final price = TextEditingController();
  List<dynamic> expenses = [];
  int? selectedExpenseId;
  DateTime dateTime = DateTime.now();
  bool distributionDateChosen=false;
  bool saving = false, loadingStock=true, stockAttempted=false;
  final stockDraft=FeedDistributionDraft();
  final stockOperationId=newOperationUuid();
  Map<String,dynamic>? stockCatalog, stockRequest;
  Future<void> loadStock() async {
    try {
      final value=await widget.apiService.get('/feed-supplies/');
      if(mounted && value is Map<String,dynamic> && value['stock_contract']==1)setState(()=>stockCatalog=value);
    } catch(_) {} finally {if(mounted)setState(()=>loadingStock=false);}
  }
  Future<void> saveStock() async {
    if(saving || loadingStock)return;
    setState(()=>saving=true);
    try {
      stockRequest ??= {...stockDraft.payload(stockCatalog!,widget.lotId,quantity.text,note.text),
        'operation_uuid':stockOperationId,'distribution_at':(distributionDateChosen?dateTime:DateTime.now()).toUtc().toIso8601String()};
      if(!widget.apiService.hasUnifiedOfflineSession) {
        stockRequest!.remove('_feed_dependencies');stockRequest!.remove('supply_parent_uuid');
      }
      stockAttempted=true;
      final value=await widget.apiService.post('/alimentation/distributions/',stockRequest!);
      if(value is! Map || (value['id']==null && value['local_only']!=true))throw StateError('Résultat non confirmé.');
      if(mounted) {if(value['local_only']==true){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enregistré sur l’appareil — synchronisation en attente')));}else{v2Confirmed(context,message:'Distribution enregistrée');}}
    } catch(e) {if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(stockAttempted?'Résultat à vérifier. Renvoyer conservera la même opération, sans double sortie.':e.toString())));}
    finally {if(mounted)setState(()=>saving=false);}
  }

  @override
  void initState() {
    super.initState();
    _loadExpenses();
    loadStock();
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





  Future<void> _save() async {
    if(stockCatalog!=null){await saveStock();return;}
    if (saving || loadingStock || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.apiService.createFeedDistribution(
        lotId: widget.lotId,
        distributedAt: distributionDateChosen?dateTime:DateTime.now(),
        feedName: feedName.text.trim(),
        quantityKg: double.parse(quantity.text.trim().replaceAll(',', '.')),
        pricePerKg: price.text.trim().isEmpty
            ? null
            : double.parse(MoneyInput.canonical(price.text)),
        expenseId: selectedExpenseId,
        note: note.text.trim(),
      );
      if (mounted) {if(widget.apiService.hasUnifiedOfflineSession && widget.apiService.lastOperationMessage!=null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.apiService.lastOperationMessage!)));}else{v2Confirmed(context,message:'Distribution enregistrée');}}
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
      child: V2Scaffold(protectDraft:true,busy:saving,
        appBar: V2AppBar(title:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(context.tr('add_feed_distribution')),Text(widget.lotName,style:const TextStyle(fontSize:14))])),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  V2Pair(first:V2PickerTile(key:const Key('feedDatePicker'),label:'Date de distribution *',value:_feedDate(dateTime),icon:Icons.calendar_month_outlined,
                    onTap:saving || stockAttempted?null:()async{final day=await showDatePicker(context:context,initialDate:dateTime,firstDate:DateTime(2000),lastDate:DateTime.now());if(day!=null && mounted && context.mounted){distributionDateChosen=true;setState(()=>dateTime=DateTime(day.year,day.month,day.day,dateTime.hour,dateTime.minute,dateTime.second,dateTime.millisecond,dateTime.microsecond));V2DraftScope.maybeOf(context)?.markChanged();}}),
                    second:V2PickerTile(key:const Key('feedTimePicker'),label:'Heure *',value:_feedTime(dateTime),icon:Icons.schedule,
                    onTap:saving || stockAttempted?null:()async{final time=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(dateTime),builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(alwaysUse24HourFormat:true),child:child!));if(time!=null && mounted && context.mounted){distributionDateChosen=true;setState(()=>dateTime=DateTime(dateTime.year,dateTime.month,dateTime.day,time.hour,time.minute,dateTime.second,dateTime.millisecond,dateTime.microsecond));V2DraftScope.maybeOf(context)?.markChanged();}})),
                  const SizedBox(height: 14),
                  if(loadingStock)const LinearProgressIndicator(),
                  if(!loadingStock && stockCatalog==null)const Text('Distribution non rattachée : aucun stock physique ne sera déduit. Rechargez le référentiel pour utiliser un stock suivi.'),
                  if(stockCatalog!=null)FeedDistributionFields(draft:stockDraft,catalog:stockCatalog!,lotId:widget.lotId,editable:!saving && !stockAttempted,quantityField:V2Field(child:TextFormField(
                    key: const Key('feedQuantityField'),
                    enabled:stockCatalog==null || (!stockAttempted && !saving),
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: V2InputDecoration(labelText: '${context.tr('feed_quantity')} *',prefixIcon:const Icon(Icons.scale_outlined),),
                    validator: (value) {
                      final parsed = MoneyInput.number(value??'')?.toDouble();
                      return parsed == null || !parsed.isFinite || parsed <= 0
                          ? context.tr('feed_invalid_quantity')
                          : null;
                    },
                  ))),
                  if(stockCatalog==null) V2Field(child:TextFormField(
                    key: const Key('feedNameField'),
                    controller: feedName,
                    maxLength: 120,
                    decoration: V2InputDecoration(labelText: context.tr('feed_name'),),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? context.tr('feed_invalid_name')
                        : null,
                  )),
                  if(stockCatalog==null) V2Field(child:TextFormField(
                    key: const Key('feedQuantityField'),
                    enabled:stockCatalog==null || (!stockAttempted && !saving),
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: V2InputDecoration(labelText: '${context.tr('feed_quantity')} *',prefixIcon:const Icon(Icons.scale_outlined),),
                    validator: (value) {
                      final parsed = MoneyInput.number(value??'')?.toDouble();
                      return parsed == null || !parsed.isFinite || parsed <= 0
                          ? context.tr('feed_invalid_quantity')
                          : null;
                    },
                  )),
                  V2Field(child:TextFormField(
                    key: const Key('feedNoteField'),
                    enabled:stockCatalog==null || (!stockAttempted && !saving),
                    controller: note,
                    maxLines: 2,
                    decoration: V2InputDecoration(labelText: context.tr('feed_note'),hintText:'Ex. : distribution du jour',prefixIcon:const Icon(Icons.note_alt_outlined),),
                  )),
                  if(stockCatalog==null) ExpansionTile(
                    title: Text(context.tr('feed_cost_optional')),
                    children: [
                      Text(context.tr('feed_cost_hint')),
                      if (expenses.isNotEmpty)
                        V2Field(child:DropdownButtonFormField<int>(
                          key: const Key('feedExpenseDropdown'),
                          isExpanded: true,
                          initialValue: selectedExpenseId ?? 0,
                          decoration: V2InputDecoration(
                            labelText: context.tr('feed_existing_expense'),),
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
                        )),
                      V2Field(child:TextFormField(
                        key: const Key('feedPriceField'),
                        inputFormatters: [MoneyInputFormatter()],
                  controller: price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: V2InputDecoration(labelText: context.tr('feed_price_kg'),),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final amount = double.tryParse(value.trim().replaceAll(',', '.'));
                          return amount == null || !amount.isFinite || amount < 0
                              ? context.tr('feed_invalid_price')
                              : null;
                        },
                      )),
                    ],
                  ),
                  const SizedBox(height: 18),
                  V2Pair(first:OutlinedButton(onPressed:saving?null:()=>Navigator.of(context).maybePop(),child:const Text('Annuler')),
                    second:FilledButton.icon(key:const Key('saveFeedDistribution'),onPressed:saving || loadingStock?null:_save,
                      icon:const Icon(Icons.save_outlined),label:Text(context.tr('save')))),

                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
