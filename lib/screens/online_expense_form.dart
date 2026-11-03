part of 'add_depense_screen.dart';

/// HTTP adapter of the shared expense fields and input contract. No local
/// outbox, grant, new endpoint, automatic retry or alternative business ledger.
class _OnlineExpenseForm extends StatefulWidget {
  const _OnlineExpenseForm({required this.api,this.readOnly=false});
  final bool readOnly;
  final ApiService api;
  @override
  State<_OnlineExpenseForm> createState() => _OnlineExpenseFormState();
}

class _OnlineExpenseFormState extends State<_OnlineExpenseForm> {
  final amount = TextEditingController(), note = TextEditingController();
  final vaccine=VaccineSupplyDraft();
  final vaccineCategories=<int>{};
  bool get wantsVaccine=>vaccineCategories.contains(categoryId);
  String get supplyPath=>wantsVaccine?'/vaccine-supplies/':'/feed-supplies/';
  final feed = FeedSupplyDraft();
  final feedOperationId = newOperationUuid();
  final feedCategories = <int>{};
  Map<String,dynamic>? feedCatalog, pendingFeed;
  bool loadingFeed = false, feedLocalRecorded=false;
  bool get wantsFeed => (feedCategories.contains(categoryId) && !widget.api.hasUnifiedOfflineSession) || wantsVaccine;

  Future<void> selectCategory(int? value) async {
    setState(() {categoryId=value; error=null;feedCatalog=null;});
    if(!wantsFeed || feedCatalog!=null)return;
    setState(()=>loadingFeed=true);
    try {
      final data=await widget.api.get(supplyPath);
      if(!mounted || !sameToken)return;
      if(data is! Map<String,dynamic> || data['confirmed']!=true ||
          data['products'] is! List || data['species'] is! List || data['lots'] is! List || (widget.api.lastReadWasCached && data['local_estimate']!=true)) {
        throw StateError('Catalogue non confirmé');
      }
      setState(()=>feedCatalog=data);
    } catch(_) {if(mounted)setState(()=>error='Catalogue d’aliments indisponible. Rechargez les références avant de poursuivre.');}
    finally {if(mounted)setState(()=>loadingFeed=false);}
  }

  Future<void> sendFeed(Map<String,dynamic> body) async {
    // Prepared sessions use the existing durable outbox, connected sessions use HTTP.
    final result=await widget.api.post('/depenses/create/',body);
    if(!mounted || !sameToken)throw StateError('Session changed');
    if(widget.api.hasUnifiedOfflineSession && result is Map && result['local_only']==true && result['operation_id']==feedOperationId) {
      setState(() {confirmed=true;feedLocalRecorded=true;error=null;});
      try {final fresh=await widget.api.get(supplyPath);if(mounted && sameToken && fresh is Map<String,dynamic>)setState(()=>feedCatalog=fresh);} catch(_) {}
      return;
    }
    if(result is! Map || result['id'] is! int || result['stock_confirmed']!=true || result['operation_uuid']!=feedOperationId) {
      throw StateError('Stock non confirmé');
    }
    setState(() {confirmed=true;error=null;});
    try {
      final fresh=await widget.api.get(supplyPath);
      if(mounted && sameToken && fresh is Map<String,dynamic> && fresh['confirmed']==true && !(widget.api.lastReadWasCached && fresh['local_estimate']!=true)) {
        setState(()=>feedCatalog=fresh);
      }
    } catch(_) {if(mounted && sameToken)setState(()=>feedCatalog=null);}

  }

  Future<void> retryFeed() async {
    if(busy || pendingFeed==null || !sameToken || confirmed)return;
    setState(()=>busy=true);
    try {
      final value=await access();
      if(value.message!=null)throw StateError('Accès refusé');
      await sendFeed(pendingFeed!);
    } catch(_) {if(mounted)setState(()=>error='Résultat non confirmé. La même opération est conservée pour vérification ; ne créez pas une autre dépense.');}
    finally {if(mounted)setState(()=>busy=false);}
  }
  late final dates = ExpenseBusinessDate(tz.getLocation('Europe/Paris'));
  late ExpenseBusinessDay day = dates.businessDayOf(DateTime.now().toUtc());
  late final token = ApiService.sessionIdentity;
  TerrainEntryAccess? origin;
  List<ExpenseLotSelection> lots = [];
  List<(int, String)> categories = [];
  ExpenseLotSelection? lot;
  int? categoryId;
  Map<String, ExpenseInputError> errors = {};
  bool busy = true,
      blocked = false,
      attempted = false,
      confirmed = false,
      ready = false;
  String? error;
  bool get sameToken => token == (ApiService.sessionIdentity);
  bool get editable => !widget.readOnly && ready && !busy && !blocked && !attempted && sameToken;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    feed.dispose();vaccine.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<TerrainEntryAccess> access() async {
    final value = await TerrainEntryAccess.read(widget.api, {
      'expenses.create',
    });
    if (!sameToken ||
        (origin != null &&
            (value.rights.userId != origin!.rights.userId ||
                value.rights.farmId != origin!.rights.farmId))) {
      throw StateError('Session changed');
    }
    return value;
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        busy = true;
        ready = false;
        error = null;
      });
    }
    try {
      final value = await access();
      if (!mounted) return;
      if (value.message != null && !(widget.readOnly && value.rights.role == 'OWNER')) {
        setState(() {
          blocked = true;
          error = value.message;
        });
        return;
      }
      origin = value;
      final values = await Future.wait([
        widget.api.getActiveLots(),
        widget.api.getCategoriesDepense(),
      ]);
      if (!mounted) return;
      if (!sameToken) throw StateError('Session changed');
      final selection = ExpenseSelectionContext(
        farmId: value.rights.farmId,
        authorId: value.rights.userId,
      );
      final nextLots = [
        for (final row in values[0])
          ExpenseLotSelection.fromProjectedRow({
            'data': Map<String, dynamic>.from(row as Map),
            'state': 'CONFIRMED',
          }, origin: selection),
      ];
      final nextCategories = <(int, String)>[];
      feedCategories.clear();
      for (final row in values[1]) {
        if (row is! Map ||
            row['id'] is! int ||
            row['nom'] is! String ||
            (row['exploitation'] != null &&
                row['exploitation'] != value.rights.farmId)) {
          throw StateError('Invalid category');
        }
        nextCategories.add((row['id'] as int, row['nom'] as String));
        if(row['stock_purpose']=='VACCINE')vaccineCategories.add(row['id'] as int);
        if(row['stock_purpose']=='FEED')feedCategories.add(row['id'] as int);
      }
      setState(() {
        lots = nextLots;
        categories = nextCategories;
        lot = null;
        categoryId = null;
        ready = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Chargement indisponible. Vérifiez votre connexion et votre compte.';
          blocked = !sameToken;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseDate() async {}

  Future<void> submit() async {
    if (!editable || loadingFeed) return;
    Map<String,dynamic>? supply;
    if(wantsFeed) {
      try {
        if(feedCatalog==null)throw const FormatException('Catalogue d’aliments requis.');
        supply=wantsVaccine?vaccine.payload():feed.payload();
      } catch(e) {setState(()=>error=e.toString());return;}
    }
    day=dates.businessDayOf(DateTime.now().toUtc());
    final input = ExpenseInputContract.validate(
      lotRef: lot?.reference,
      categoryId: categoryId,
      amount: amount.text,
      note: note.text,
    );
    setState(() => errors = input.errors);
    if (!input.isValid) return;
    if (!lots.contains(lot) || !categories.any((c) => c.$1 == categoryId)) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      dates.representativeUtc(day, nowUtc: DateTime.now().toUtc());
      // Re-read server policy and rights immediately before a single POST.
      // HasExploitation remains authoritative if policy changes after this read.
      final value = await access();
      if (!mounted) return;
      if (value.message != null) {
        setState(() {
          blocked = true;
          error = value.message;
        });
        return;
      }
      if (!sameToken) throw StateError('Session changed');
      attempted = true;
      final body = <String,dynamic>{
        'lot': lot!.reference['server_id'],
        'categorie': categoryId,
        'montant': input.payload!['montant'],
        'note': input.payload!['note'],
        'date':
            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        if(supply!=null) ...{'operation_uuid':feedOperationId,(wantsVaccine?'vaccine_supply':'feed_supply'):supply},
      };
      if(supply!=null) {pendingFeed=body;await sendFeed(body);return;}
      final result = await widget.api.post('/depenses/create/',body);
      if (!mounted) return;
      if (!sameToken) {
        blocked = true;
        throw StateError('Session changed');
      }
      if (result is! Map || (result['local_only']!=true && (result['id'] is! int || (result['id'] as int) < 1))) {
        throw StateError('Unconfirmed response');
      }
      setState(() => confirmed = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          blocked = blocked || !sameToken;
          error = attempted
              ? 'Résultat non confirmé. Consultez les dépenses avant toute nouvelle saisie. Aucun renvoi automatique ne sera effectué.'
              : 'Impossible de vérifier votre accès. Aucune dépense envoyée ; réessayez avec Internet.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(data:terreEtOrTheme(context),child:Builder(builder:(context)=>Scaffold(
    appBar: AppBar(title: const Text('Nouvelle dépense')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const TerreEtOrHeader(icon:Icons.receipt_long_outlined,title:'Nouvelle dépense',subtitle:'Renseignez les informations de votre dépense'),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!, key: const Key('expense-error')),
        if (confirmed)
          Text(widget.api.operationFeedback(feedLocalRecorded?'Enregistré sur cet appareil. Stock estimé ; confirmation serveur en attente.':pendingFeed!=null?'Dépense et approvisionnement confirmés par le serveur.':'Dépense confirmée par le serveur.'),key:const Key('expense-status')),
        if (!blocked && sameToken) ...[
          ExpenseFields(
            lots: lots,
            categories: categories,
            categoryKey: categories,
            lot: lot,
            categoryId: categoryId,
            amount: amount,
            note: note,
            day: day,
            editable: editable,
            fieldError: (key) => expenseFieldError(errors[key]),
            onLot: (value) => setState(() => lot = value),
            onCategory: selectCategory,
            chooseDate: chooseDate,
          ),
          if(feedCategories.contains(categoryId) && widget.api.hasUnifiedOfflineSession)
            const Text('Les opérations locales restent en attente de validation du serveur.'),
          if(wantsFeed && loadingFeed) const LinearProgressIndicator(),
          if(wantsFeed && feedCatalog!=null) wantsVaccine?VaccineSupplyFields(draft:vaccine,catalog:feedCatalog!,editable:editable):FeedSupplyFields(draft:feed,catalog:feedCatalog!,editable:editable),
          if(pendingFeed!=null && attempted && !confirmed && sameToken)
            TextButton(key:const Key('feed-retry'),onPressed:busy?null:retryFeed,child:const Text('Vérifier / renvoyer la même opération')),
          if (!widget.readOnly) FilledButton(
            key: const Key('expense-submit'),
            onPressed: editable && !loadingFeed && (!wantsFeed || feedCatalog!=null) ? submit : null,
            child: const Text('Enregistrer'),
          ),
          if (!attempted)
            TextButton(
              onPressed: busy ? null : load,
              child: const Text('Recharger les références'),
            ),
        ],
        if (!confirmed && !widget.api.hasUnifiedOfflineSession)
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FarmerAccessScreen()),
            ),
            child: const Text('Ouvrir l’espace éleveur'),
          ),
      ],
    ),
  )));
}
