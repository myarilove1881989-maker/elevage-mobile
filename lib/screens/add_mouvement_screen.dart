import '../widgets/micro_feedback.dart';
import '../services/money_input.dart';
import '../widgets/v2_components.dart';
import 'package:flutter/material.dart';
import '../widgets/operation_status.dart';
import '../l10n/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/api_service.dart';
import '../models/lot.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/terrain_entry_gate.dart';

class AddMouvementScreen extends StatelessWidget {
  const AddMouvementScreen({super.key,required this.apiService});
  final ApiService apiService;
  @override
  Widget build(BuildContext context)=>TerrainEntryGate(api:apiService,
    actions:const {'animal_sales.create','egg_sales.create','births.create','mortality.create','donations.create','thefts.create'},
    ownerBuilder:(_)=>_ClassicMouvementScreen(apiService:apiService,readOnly:true),
    builder:(_)=>_ClassicMouvementScreen(apiService:apiService));
}

class _ClassicMouvementScreen extends StatefulWidget {
  final ApiService apiService;

  const _ClassicMouvementScreen({required this.apiService,this.readOnly=false});
  final bool readOnly;

  @override
  State<_ClassicMouvementScreen> createState() => _AddMouvementScreenState();
}

class _AddMouvementScreenState extends State<_ClassicMouvementScreen> {
  List<Lot> lots = [];
  int? selectedLotId;

  // 🔥 CLIENTS
  List<dynamic> clients = [];
  int? selectedClientId;

  String selectedType = "VENTE";
  String selectedProduct = "ANIMAUX";

  final TextEditingController quantiteController = TextEditingController();
  final TextEditingController prixController = TextEditingController();
  final TextEditingController stillbornController = TextEditingController(
    text: '0',
  );
  final TextEditingController birthNoteController = TextEditingController();
  final TextEditingController birthLotNameController = TextEditingController();
  String birthProductionType = 'CHAIR';
  final TextEditingController traysController = TextEditingController(
    text: '0',
  );
  final TextEditingController extraEggsController = TextEditingController(
    text: '0',
  );
  final TextEditingController totalPriceController = TextEditingController();
  int? eggStockAvailable;
  bool eggOriginsComplete = false;
  bool eggStockLoading = false;

  DateTime selectedDate = DateTime.now();

  bool isLoading = true;
  bool isSubmitting = false;

  List<String> types = ["VENTE", "MORTALITE", "DON", "VOL", "NAISSANCE"];

  String movementLabel(String type) {
    switch (type) {
      case 'VENTE':
        return context.tr('sale');
      case 'MORTALITE':
        return context.tr('mortality');
      case 'DON':
        return context.tr('donation');
      case 'VOL':
        return context.tr('theft');
      case 'NAISSANCE':
        return context.tr('birth');
      default:
        return type;
    }
  }

  @override
  void initState() {
    super.initState();
    birthLotNameController.text = defaultBirthLotName(selectedDate);
    fetchData();
  }

  String defaultBirthLotName(DateTime value) =>
      'Naissance - '
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  int? get birthLivePreview {
    final total = int.tryParse(quantiteController.text.trim());
    final stillborn = int.tryParse(stillbornController.text.trim());
    if (total == null ||
        stillborn == null ||
        stillborn < 0 ||
        total <= stillborn) {
      return null;
    }
    return total - stillborn;
  }

  // ================= FETCH DATA =================
  Future<void> fetchData() async {
    try {
      if(!widget.readOnly) {
        final access=await TerrainEntryAccess.read(widget.apiService, const {'animal_sales.create','egg_sales.create','births.create','mortality.create','donations.create','thefts.create'});
        final rights=access.rights;
        types=types.where((type) => type=='VENTE'
          ? rights.allows('animal_sales.create') || rights.allows('egg_sales.create')
          : rights.allows({'MORTALITE':'mortality.create','DON':'donations.create','VOL':'thefts.create','NAISSANCE':'births.create'}[type]!)).toList();
        if(types.isNotEmpty && !types.contains(selectedType)) selectedType=types.first;
        if(!rights.allows('animal_sales.create') && rights.allows('egg_sales.create')) selectedProduct='OEUFS';
      }
      final lotsResult = await widget.apiService.getActiveLots();
      final clientsResult = await widget.apiService.getClients();

      final parsedLots = lotsResult.map((json) => Lot.fromJson(json)).toList();

      if (!mounted) return;

      setState(() {
        lots = parsedLots;
        clients = clientsResult;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      showMessage("Erreur chargement données");
    }
  }

  // ================= GET LOT =================
  List<Lot> get selectableLots =>
      selectedType == 'VENTE' && selectedProduct == 'OEUFS'
      ? lots.where((lot) => lot.typeProduction == 'OEUFS').toList()
      : lots;

  Lot? get selectedLot {
    for (final lot in selectableLots) {
      if (lot.id == selectedLotId) return lot;
    }
    return null;
  }

  Future<void> loadEggStock(int lotId) async {
    setState(() {
      eggStockLoading = true;
      eggStockAvailable = null;
      eggOriginsComplete = false;
    });
    try {
      final stock = await widget.apiService.getDatedEggStock(lotId);
      if (!mounted || selectedLotId != lotId || selectedProduct != 'OEUFS')
        return;
      setState(() {
        eggStockAvailable = (stock['stock_global'] as num).toInt();
        eggOriginsComplete = stock['origines_completes'] == true;
        eggStockLoading = false;
      });
    } catch (_) {
      if (!mounted || selectedLotId != lotId || selectedProduct != 'OEUFS')
        return;
      setState(() => eggStockLoading = false);
    }
  }

  // ================= MESSAGE =================
  void showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ================= CREATE CLIENT =================
  Future<void> showCreateClientDialog() async {
    if(widget.readOnly || !await TerrainEntryGate.allowClassic(context,widget.apiService,{'clients.create'}) || !mounted) return;
    final nomController = TextEditingController();
    final telController = TextEditingController();
    final villeController = TextEditingController();
    var pays = AppSettings.instance.countryCode;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => V2AlertDialog(
          title: Text(context.tr('new_customer')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                V2Field(child:TextField(
                  controller: nomController,
                  decoration: V2InputDecoration(labelText: context.tr('name'),),
                )),
                V2Field(child:TextField(
                  controller: telController,
                  keyboardType: TextInputType.phone,
                  decoration: V2InputDecoration(labelText: context.tr('phone'),),
                )),
                const SizedBox(height: 12),
                V2Field(child:DropdownButtonFormField<String>(

                  isExpanded: true,

                  value: pays.isEmpty ? null : pays,

                  decoration: V2InputDecoration(
                    labelText:
                        '${context.tr('country')} (${context.tr('optional')})',),
                  items:
                      AppSettings.sortedCountries(
                            AppSettings.instance.languageCode,
                          )
                          .map(
                            (country) => DropdownMenuItem<String>(
                              value: country.code,
                              child: Text(
                                country.label(
                                  AppSettings.instance.languageCode,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    setDialogState(() => pays = value ?? '');
                  },
                )),
                V2Field(child:TextField(
                  controller: villeController,
                  decoration: V2InputDecoration(
                    labelText:
                        '${context.tr('city')} (${context.tr('optional')})',),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text(context.tr('cancel')),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            BusinessCommand(api: widget.apiService, actions: const {'clients.create'}, child: ElevatedButton(
              child: Text(context.tr('add')),
              onPressed: () async {
                final nom = nomController.text.trim();
                final telephone = telController.text.trim();

                if (nom.isEmpty || telephone.isEmpty) {
                  showMessage("Tous les champs sont obligatoires");
                  return;
                }

                await widget.apiService.createClient(
                  nom,
                  telephone,
                  pays: pays,
                  ville: villeController.text.trim(),
                );

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                await fetchData();

                if (!mounted) return;
                showMessage(widget.apiService.operationFeedback("Client créé"));
              },
            )),
          ],
        ),
      ),
    );

    nomController.dispose();
    telController.dispose();
    villeController.dispose();
  }

  String? automaticPrice;
  String? originPriceMessage;
  Future<void> prefillOriginPrice() async {
    if(!{'MORTALITE','DON','VOL'}.contains(selectedType) || selectedLotId==null)return;
    if(prixController.text.isNotEmpty && prixController.text!=automaticPrice)return;
    final id=selectedLotId,type=selectedType,identity=ApiService.sessionIdentity;
    try {
      final detail=await widget.apiService.getLotDetail(id!);
      if(!mounted || selectedLotId!=id || selectedType!=type || identity!=ApiService.sessionIdentity)return;
      if(prixController.text.isNotEmpty && prixController.text!=automaticPrice)return;
      final value=detail['prix_unitaire_origine'];
      setState(() {automaticPrice=value==null?null:MoneyInput.display('$value');
        prixController.text=automaticPrice??'';
        originPriceMessage=value==null?'Prix d’origine non déterminable. Renseignez une valeur si nécessaire.':null;});
    }catch(_) {if(mounted)setState(()=>originPriceMessage='Prix d’origine indisponible. Vérifiez la connexion.');}
  }

  Object _confirmationCue = Object();
  Future<void> movementConfirmed() async {
    if(widget.apiService.lastOperationMessage!=null) {
      showMessage(widget.apiService.lastOperationMessage!);return;
    }
    MicroFeedback.confirmed(context, operation: _confirmationCue);
    V2DraftScope.maybeOf(context)?.confirmed();
    setState(() {quantiteController.clear();prixController.clear();totalPriceController.clear();
      traysController.text='0';extraEggsController.text='0';isSubmitting=false;});
    showMessage('Mouvement enregistré. Vous pouvez saisir le suivant.');
    await fetchData();
    await prefillOriginPrice();
    if(mounted && selectedProduct=='OEUFS' && selectedLotId!=null)await loadEggStock(selectedLotId!);
  }

  // ================= SUBMIT =================
  Future<void> submit() async {
    final action = selectedType == 'VENTE'
      ? (selectedProduct == 'OEUFS' ? 'egg_sales.create' : 'animal_sales.create')
      : {'MORTALITE':'mortality.create','DON':'donations.create','VOL':'thefts.create','NAISSANCE':'births.create'}[selectedType];
    if(widget.readOnly || action==null || !await TerrainEntryGate.allowClassic(context,widget.apiService,{action}) || !mounted) return;
    if (isSubmitting) return;
    _confirmationCue = Object();

    if (selectedLotId == null) {
      showMessage("Sélectionnez un lot");
      return;
    }

    if (selectedType == "VENTE" && selectedClientId == null) {
      showMessage("Sélectionnez un client");
      return;
    }

    if (selectedType == 'NAISSANCE') {
      final total = int.tryParse(quantiteController.text.trim());
      final stillborn = int.tryParse(stillbornController.text.trim());
      if (stillborn == null || stillborn < 0) {
        showMessage(context.tr('birth_invalid_stillborn'));
        return;
      }
      if (total == null || total <= stillborn) {
        showMessage(context.tr('birth_invalid_live'));
        return;
      }
      final newLotName = birthLotNameController.text.trim();
      if (newLotName.isEmpty || newLotName.length > 100) {
        showMessage(context.tr('birth_new_lot_required'));
        return;
      }
      setState(() => isSubmitting = true);
      try {
        final saved = await widget.apiService.createBirth(
          lotId: selectedLotId!,
          totalBirths: total,
          stillborn: stillborn,
          newLotName: newLotName,
          productionType: birthProductionType,
          date: DateTime.now(),
          note: birthNoteController.text.trim(),
        );
        if (mounted) {
          if(saved['local_only']==true) {
            showMessage(widget.apiService.operationFeedback('Naissance enregistrée.'));
            return;
          }
          setState(() => isSubmitting = false);
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => V2AlertDialog(
              title: Text(context.tr('birth_saved')),
              content: Text(
                '${saved['nouveau_lot']['nom']} : '
                '${saved['nes_vivants']} ${context.tr('birth_live').toLowerCase()} · '
                '${saved['mort_nes'] ?? stillborn} ${context.tr('birth_stillborn').toLowerCase()}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(context.tr('close')),
                ),
              ],
            ),
          );
          if (mounted) await movementConfirmed();
        }
      } catch (error) {
        if (mounted)
          showMessage(unconfirmedOperationMessage);
      } finally {
        if (mounted) setState(() => isSubmitting = false);
      }
      return;
    }

    if (selectedType == "VENTE" && selectedProduct == "OEUFS") {
      final trays = int.tryParse(traysController.text.trim());
      final extra = int.tryParse(extraEggsController.text.trim());
      if (trays == null ||
          trays < 0 ||
          extra == null ||
          extra < 0 ||
          extra >= 30 ||
          trays * 30 + extra <= 0) {
        showMessage(context.tr('sale_invalid_quantity'));
        return;
      }
      final price = MoneyInput.canonical(totalPriceController.text);
      if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(price) ||
          (double.tryParse(price) ?? 0) <= 0) {
        showMessage(context.tr('sale_invalid_total'));
        return;
      }
      if (eggStockAvailable == null) {
        showMessage(context.tr('sale_stock_unavailable'));
        return;
      }
      if (!eggOriginsComplete) {
        showMessage(context.tr('sale_origins_incomplete'));
        return;
      }
      if (trays * 30 + extra > eggStockAvailable!) {
        showMessage(
          '${context.tr('sale_stock_insufficient')} : '
          '$eggStockAvailable ${context.tr('egg_eggs_short')}',
        );
        return;
      }
      setState(() => isSubmitting = true);
      try {
        await widget.apiService.createMixedEggSale(
          lotId: selectedLotId!,
          clientId: selectedClientId!,
          fullTrays: trays,
          extraEggs: extra,
          totalPrice: price,
          date: DateTime.now(),
        );
        if (mounted) await movementConfirmed();
      } catch (error) {
        if (mounted)
          showMessage(unconfirmedOperationMessage);
      } finally {
        if (mounted) setState(() => isSubmitting = false);
      }
      return;
    }

    if (quantiteController.text.isEmpty || prixController.text.isEmpty) {
      showMessage("Tous les champs sont obligatoires");
      return;
    }

    final quantite = int.tryParse(quantiteController.text.trim());
    final prix = MoneyInput.number(prixController.text)?.toDouble();

    if (quantite == null || prix == null) {
      showMessage("Valeurs invalides");
      return;
    }

    if (quantite <= 0) {
      showMessage("Quantité doit être > 0");
      return;
    }

    if (selectedType == 'VENTE' ? prix <= 0 : prix < 0) {
      showMessage("Prix invalide");
      return;
    }

    if (selectedLot != null && quantite > selectedLot!.stock) {
      showMessage("Stock insuffisant (${selectedLot!.stock})");
      return;
    }

    setState(() => isSubmitting = true);

    try {
      final success = await widget.apiService.createMouvement(
        lotId: selectedLotId!,
        type: selectedType,
        quantite: quantite,
        prixUnitaire: prix,
        date: DateTime.now(),
        clientId: selectedClientId,
      );

      if (!mounted) return;

      if (success) {
        await movementConfirmed();
      } else {
        showMessage("Erreur création mouvement");
      }
    } catch (e) {
      showMessage("Erreur serveur");
    }

    if (!mounted) return;
    setState(() => isSubmitting = false);
  }

  @override
  void dispose() {
    quantiteController.dispose();
    prixController.dispose();
    stillbornController.dispose();
    birthNoteController.dispose();
    birthLotNameController.dispose();
    traysController.dispose();
    extraEggsController.dispose();
    totalPriceController.dispose();
    super.dispose();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const V2Scaffold(protectDraft:true,body: Center(child: CircularProgressIndicator()));
    }

    return AbsorbPointer(
      absorbing: isSubmitting,
      child: Theme(
        data: terreEtOrTheme(context),
        child: V2Scaffold(protectDraft:true,
          appBar: V2AppBar(title: Text(context.tr('add_movement'))),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TerreEtOrHeader(
                    icon: Icons.swap_horiz_rounded,
                    title: context.tr('add_movement'),
                    subtitle: AppSettings.instance.languageCode == 'en'
                        ? 'Record a sale, mortality, donation, theft or birth'
                        : 'Enregistrez une vente, mortalité, un don, un vol ou une naissance',
                  ),
                  TerreEtOrPanel(
                    child: Column(
                      children: [
                        // TYPE
                        V2Field(child:DropdownButtonFormField<String>(

                          isExpanded: true,

                          key: const Key('movementTypeDropdown'),
                          value: selectedType,
                          items: types.map((t) {
                            return DropdownMenuItem(
                              value: t,
                              child: Text(movementLabel(t)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedType = value!;
                              selectedClientId = null;
                              eggStockAvailable = null;
                              eggOriginsComplete = false;
                            });
                            prefillOriginPrice();
                          },
                          decoration: V2InputDecoration(
                            labelText: context.tr('movement_type'),),
                        )),

                        const SizedBox(height: 16),

                        if (selectedType == 'VENTE') ...[
                          V2Field(child:DropdownButtonFormField<String>(

                            isExpanded: true,

                            key: const Key('saleProductDropdown'),
                            value: selectedProduct,
                            decoration: V2InputDecoration(
                              labelText: context.tr('sale_product'),),
                            items: [
                              DropdownMenuItem(
                                value: 'ANIMAUX',
                                child: Text(context.tr('sale_animals')),
                              ),
                              DropdownMenuItem(
                                value: 'OEUFS',
                                child: Text(context.tr('sale_eggs')),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedProduct = value ?? 'ANIMAUX';
                                selectedLotId = null;
                                eggStockAvailable = null;
                                eggOriginsComplete = false;
                              });
                            },
                          )),
                          const SizedBox(height: 16),
                        ],

                        // LOT
                        V2Field(child:DropdownButtonFormField<int>(

                          isExpanded: true,

                          key: const Key('movementLotDropdown'),
                          value: selectedLotId,
                          items: selectableLots.map((lot) {
                            return DropdownMenuItem<int>(
                              value: lot.id,
                              child: Text(lot.nom),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedLotId = value;
                              eggStockAvailable = null;
                              eggOriginsComplete = false;
                            });
                            prefillOriginPrice();
                            if (value != null &&
                                selectedType == 'VENTE' &&
                                selectedProduct == 'OEUFS') {
                              loadEggStock(value);
                            }
                          },
                          decoration: V2InputDecoration(
                            labelText: selectedType == 'NAISSANCE'
                                ? context.tr('birth_parent')
                                : context.tr('batch'),),
                        )),
                        if (selectedType == 'NAISSANCE' && selectedLot != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${context.tr('birth_species')} : ${selectedLot!.especeNom ?? ''}',
                              key: const Key('birthSpecies'),
                            ),
                          ),
                        if (selectedType == 'VENTE' &&
                            selectedProduct == 'OEUFS' &&
                            selectableLots.isEmpty)
                          Text(context.tr('egg_stock_empty')),

                        const SizedBox(height: 16),

                        // 🔥 CLIENT
                        if (selectedType == "VENTE")
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: V2Field(child:DropdownButtonFormField<int>(

                                      isExpanded: true,

                                      key: const Key('movementClientDropdown'),
                                      value: selectedClientId,
                                      items: clients.map((c) {
                                        return DropdownMenuItem<int>(
                                          value: c["id"],
                                          child: Text(c["nom"]),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          selectedClientId = value;
                                        });
                                      },
                                      decoration: V2InputDecoration(
                                        labelText: context.tr('customer'),),
                                    )),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_circle,
                                      color: Colors.green,
                                    ),
                                    onPressed: showCreateClientDialog,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),

                        // STOCK
                        if (selectedLot != null &&
                            selectedType == 'VENTE' &&
                            selectedProduct == 'OEUFS')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: eggStockLoading
                                ? const CircularProgressIndicator()
                                : eggStockAvailable == null
                                ? TextButton(
                                    key: const Key('eggStockRetry'),
                                    onPressed: () =>
                                        loadEggStock(selectedLotId!),
                                    child: Text(context.tr('sale_stock_retry')),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${context.tr('sale_stock_eggs')} : '
                                        '$eggStockAvailable ${context.tr('egg_eggs_short')} · '
                                        '${eggStockAvailable! ~/ 30} ${context.tr('egg_trays_short')} + '
                                        '${eggStockAvailable! % 30} ${context.tr('egg_eggs_short')}',
                                        key: const Key('eggSaleStock'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (!eggOriginsComplete)
                                        Text(
                                          context.tr('sale_origins_incomplete'),
                                          key: const Key(
                                            'eggSaleOriginsIncomplete',
                                          ),
                                        ),
                                    ],
                                  ),
                          )
                        else if (selectedLot != null &&
                            selectedType != 'NAISSANCE')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Stock disponible: ${selectedLot!.stock}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),

                        // DATE
                        TerreEtOrDateTile(
                          label:
                              "${context.tr('date')} : ${v2Day(selectedDate.toLocal().toIso8601String())}",
                          onTap: null,
                        ),

                        const SizedBox(height: 16),

                        // QUANTITE
                        if (selectedType == 'VENTE' &&
                            selectedProduct == 'OEUFS') ...[
                          V2Field(child:TextField(
                            key: const Key('eggSaleTrays'),
                            controller: traysController,
                            keyboardType: TextInputType.number,
                            decoration: V2InputDecoration(
                              labelText: context.tr('egg_full_trays'),),
                            onChanged: (_) => setState(() {}),
                          )),
                          const SizedBox(height: 16),
                          V2Field(child:TextField(
                            key: const Key('eggSaleExtra'),
                            controller: extraEggsController,
                            keyboardType: TextInputType.number,
                            decoration: V2InputDecoration(
                              labelText: context.tr('sale_extra_eggs'),),
                            onChanged: (_) => setState(() {}),
                          )),
                          const SizedBox(height: 8),
                          Text(
                            '${context.tr('sale_total_eggs')} : '
                            '${((int.tryParse(traysController.text) ?? 0) * 30) + (int.tryParse(extraEggsController.text) ?? 0)} '
                            '${context.tr('egg_eggs_short')}',
                            key: const Key('eggSaleTotalEggs'),
                          ),
                          const SizedBox(height: 16),
                          V2Field(child:TextField(
                            key: const Key('eggSaleTotalPrice'),
                            inputFormatters: [MoneyInputFormatter()],
                  controller: totalPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: V2InputDecoration(
                              labelText:
                                  '${context.tr('sale_total_price')} '
                                  '(${AppSettings.instance.currency.symbol})',),
                          )),
                        ] else if (selectedType == 'NAISSANCE') ...[
                          V2Field(child:TextField(
                            key: const Key('birthTotal'),
                            controller: quantiteController,
                            keyboardType: TextInputType.number,
                            decoration: V2InputDecoration(
                              labelText: context.tr('birth_total'),),
                            onChanged: (_) => setState(() {}),
                          )),
                          const SizedBox(height: 16),
                          V2Field(child:TextField(
                            key: const Key('birthStillborn'),
                            controller: stillbornController,
                            keyboardType: TextInputType.number,
                            decoration: V2InputDecoration(
                              labelText: context.tr('birth_stillborn'),),
                            onChanged: (_) => setState(() {}),
                          )),
                          const SizedBox(height: 8),
                          Text(
                            '${context.tr('birth_live')} : '
                            '${birthLivePreview ?? '—'}',
                            key: const Key('birthCalculatedLive'),
                          ),
                          const SizedBox(height: 16),
                          V2Field(child:TextField(
                            key: const Key('birthNewLotName'),
                            controller: birthLotNameController,
                            decoration: V2InputDecoration(
                              labelText: context.tr('birth_new_lot'),),
                          )),
                          const SizedBox(height: 16),
                          V2Field(child:DropdownButtonFormField<String>(

                            isExpanded: true,

                            key: const Key('birthProductionType'),
                            initialValue: birthProductionType,
                            decoration: V2InputDecoration(
                              labelText: context.tr('birth_new_lot_type'),),
                            items: ['CHAIR', 'OEUFS', 'REPRODUCTION', 'AUTRE']
                                .map(
                                  (type) => DropdownMenuItem<String>(
                                    value: type,
                                    child: Text(
                                      context.tr(
                                        {
                                          'CHAIR': 'production_type_meat',
                                          'OEUFS': 'production_type_eggs',
                                          'REPRODUCTION':
                                              'production_type_reproduction',
                                          'AUTRE': 'production_type_other',
                                        }[type]!,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(
                              () => birthProductionType = value ?? 'CHAIR',
                            ),
                          )),
                          const SizedBox(height: 16),
                          V2Field(child:TextField(
                            key: const Key('birthNote'),
                            controller: birthNoteController,
                            decoration: V2InputDecoration(
                              labelText: context.tr('birth_note'),),
                          )),
                        ] else ...[
                          V2Field(child:TextField(
                            key: const Key('animalSaleQuantity'),
                            controller: quantiteController,
                            keyboardType: TextInputType.number,
                            decoration: V2InputDecoration(
                              labelText: context.tr('quantity'),),
                          )),
                          const SizedBox(height: 16),
                          V2Field(child:TextField(
                            key: const Key('animalSalePrice'),
                            inputFormatters: [MoneyInputFormatter()],
                  controller: prixController,
                            keyboardType: TextInputType.number,
                            decoration: V2InputDecoration(
                              labelText:
                                  '${context.tr('unit_price_auto')} '
                                  '(${AppSettings.instance.currency.symbol})',),
                          )),
                        ],

                        if(originPriceMessage!=null)Text(originPriceMessage!),
                        const SizedBox(height: 20),

                        // BOUTON
                        SizedBox(
                          width: double.infinity,
                          child: widget.readOnly ? const SizedBox.shrink() : ElevatedButton(
                            key: const Key('saveMovement'),
                            onPressed: isSubmitting ? null : submit,
                            child: isSubmitting
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(context.tr('validate')),
                          ),
                        ),
                      ],
                    ),
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
