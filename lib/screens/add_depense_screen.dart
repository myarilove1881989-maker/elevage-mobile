import 'dart:async';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import '../offline/expense_business_date.dart';
import '../offline/expense_form_controller.dart';
import '../offline/expense_input_contract.dart';
import '../offline/expense_preparation.dart';
import '../offline/tablet_controller.dart';
import 'farmer_access_screen.dart';
import '../services/api_service.dart';
import '../widgets/terrain_entry_gate.dart';
import '../widgets/expense_fields.dart';
import '../theme/terre_et_or_theme.dart';
part 'online_expense_form.dart';

class AddDepenseScreen extends StatefulWidget {
  const AddDepenseScreen({super.key, this.tablet,this.apiService,this.simple=false});
  final bool simple;
  final TabletController? tablet;
  final ApiService? apiService;
  @override
  State<AddDepenseScreen> createState() => _AddDepenseScreenState();
}

class _AddDepenseScreenState extends State<AddDepenseScreen> {
  final formScroll=ScrollController();
  bool resultShown=false;
  ExpenseFormController? model;
  final amount = TextEditingController(), note = TextEditingController();
  ExpenseLotSelection? lot;
  int? categoryId;
  late ExpenseBusinessDay day;
  Timer? checkTimer;
  late final ApiService? onlineApi;
  @override
  void initState() {
    super.initState();
    final tablet = widget.tablet;
    onlineApi=tablet==null?(widget.apiService??ApiService()):null;
    if (tablet != null) {
      final dates = ExpenseBusinessDate(tz.getLocation('Europe/Paris'));
      day = dates.businessDayOf(tablet.clock().toUtc());
      model = ExpenseFormController(tablet, dates)..addListener(_changed);
      model!.load();
      checkTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => model?.checkContext(),
      );
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!model!.lots.contains(lot)) lot = null;
    if (model!.categories == null) categoryId = null;
    if (model!.suspended) {
      amount.clear();
      note.clear();
      lot = null;
      categoryId = null;
    }
    setState(() {});
    if(!resultShown && !model!.busy && model!.operationId!=null) {
      resultShown=true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(mounted && formScroll.hasClients) formScroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    if(widget.apiService==null) onlineApi?.close();
    formScroll.dispose();
    checkTimer?.cancel();
    model?.removeListener(_changed);
    model?.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  String? fieldError(String key) {
    return expenseFieldError(model!.fieldErrors[key]);
  }

  Future<void> chooseDate() async {}

  Future<void> reopenOriginal() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _OriginalExpensePinDialog(personalCode:widget.simple),
    );
    if (!mounted || pin == null) return;
    await model!.reopenOriginal(pin,personalCode:widget.simple);
  }

  @override
  Widget build(BuildContext context) {
    final m = model;
    if(m==null) {
      return TerrainEntryGate(api:onlineApi!,actions:const {'expenses.create'},
        ownerBuilder:(_)=>_OnlineExpenseForm(api:onlineApi!,readOnly:true),
        builder:(_)=>_OnlineExpenseForm(api:onlineApi!));
    }
    return Theme(data:terreEtOrTheme(context),child:Builder(builder:(context)=>Scaffold(
      appBar: AppBar(title: const Text('Nouvelle dépense')),
      body: ListView(
              controller:formScroll,
              padding: const EdgeInsets.all(20),
              children: [
                const TerreEtOrHeader(icon:Icons.receipt_long_outlined,title:'Nouvelle dépense',subtitle:'Renseignez les informations de votre dépense'),
                if (m.busy) const LinearProgressIndicator(),
                Text(
                  m.resultVisible
                      ? expenseStatusText(m.result)
                      : 'Session suspendue — résultat masqué ; consultation du registre original requise.',
                  key: const Key('expense-status'),
                ),
                if (!widget.simple && m.operationId != null)
                  SelectableText('UUID : ${m.operationId}'),
                const Text(
                  'Les totaux financiers confirmés n’incluent pas cette dépense tant qu’elle reste en attente.',
                ),
                if (m.error != null)
                  Text(
                    m.error!,
                    key: const Key('expense-error'),
                    style: const TextStyle(color: Colors.red),
                  ),
                if (!m.suspended) ...[
                  if (!widget.simple && m.categories != null)
                    Text(
                      'Catégories en cache : ${m.categories!.catalog.freshness == ExpenseCacheFreshness.stale ? 'périmées' : 'fraîcheur inconnue'}, cohérence transactionnelle non vérifiée. La validation finale appartient au serveur.',
                    ),
                  ExpenseFields(
                    lots:m.lots,categories:[for(final c in m.categories?.catalog.categories ?? <ExpenseCategorySelection>[]) (c.id,c.name)],
                    categoryKey:m.categories,lot:lot,categoryId:categoryId,amount:amount,note:note,day:day,editable:m.editable,
                    fieldError:fieldError,onLot:(value)=>setState(()=>lot=value),onCategory:(value)=>setState(()=>categoryId=value),
                    chooseDate:chooseDate,
                  ),
                  if (m.dateError != null)
                    Text(m.dateError!, key: const Key('expense-date-error')),
                  FilledButton(
                    key: const Key('expense-submit'),
                    onPressed: m.editable
                        ? () => m.submit(
                            lot: lot,
                            categoryId: categoryId,
                            amount: amount.text,
                            note: note.text,
                            day: m.dates.businessDayOf(m.tablet.clock().toUtc()),
                          )
                        : null,
                    child: Text(widget.simple?'Enregistrer':'Enregistrer sur cet appareil'),
                  ),
                  if (m.operationId == null)
                    TextButton(
                      onPressed: m.busy
                          ? null
                          : () async {
                              lot = null;
                              categoryId = null;
                              await m.load();
                            },
                      child: const Text('Recharger les références locales'),
                    ),
                ],
                if (m.operationId != null)
                  TextButton(
                    key: const Key('expense-verify'),
                    onPressed: m.busy ? null : m.verify,
                    child: const Text('Vérifier le registre original'),
                  ),
                if (m.suspended && m.operationId != null)
                  TextButton(
                    key: const Key('expense-reopen-original'),
                    onPressed: m.busy ? null : reopenOriginal,
                    child: const Text(
                      'Rouvrir le profil original pour consulter',
                    ),
                  ),
                if (m.suspended) Text(widget.simple
                  ?'Reconnectez-vous pour consulter cette opération. La saisie déjà enregistrée sera conservée.'
                  :'Rouvrez manuellement le même profil et le grant original pour consulter. Le brouillon ne sera pas réactivé.'),
                const Text(
                  'Le brouillon n’est pas récupérable après fermeture complète de l’application.',
                ),
              ],
            ),
    )));
  }
}

class _OriginalExpensePinDialog extends StatefulWidget {
  const _OriginalExpensePinDialog({this.personalCode=false});
  final bool personalCode;
  @override
  State<_OriginalExpensePinDialog> createState() =>
      _OriginalExpensePinDialogState();
}

class _OriginalExpensePinDialogState extends State<_OriginalExpensePinDialog> {
  final pin = TextEditingController();
  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Consulter sous le profil original'),
    content: TextField(
      key: const Key('expense-original-pin'),
      controller: pin,
      obscureText: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText:widget.personalCode?'Code personnel':'PIN personnel existant'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, pin.text),
        child: const Text('Rouvrir et vérifier'),
      ),
    ],
  );
}
