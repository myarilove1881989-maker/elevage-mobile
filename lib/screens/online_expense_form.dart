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
        widget.api.getLots(),
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
      for (final row in values[1]) {
        if (row is! Map ||
            row['id'] is! int ||
            row['nom'] is! String ||
            (row['exploitation'] != null &&
                row['exploitation'] != value.rights.farmId)) {
          throw StateError('Invalid category');
        }
        nextCategories.add((row['id'] as int, row['nom'] as String));
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
    if (!editable) return;
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
      final result = await widget.api.post('/depenses/create/', {
        'lot': lot!.reference['server_id'],
        'categorie': categoryId,
        'montant': input.payload!['montant'],
        'note': input.payload!['note'],
        'date':
            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      });
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
          Text(widget.api.operationFeedback('Dépense confirmée par le serveur.'),key:const Key('expense-status')),
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
            onCategory: (value) => setState(() => categoryId = value),
            chooseDate: chooseDate,
          ),
          if (!widget.readOnly) FilledButton(
            key: const Key('expense-submit'),
            onPressed: editable ? submit : null,
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
