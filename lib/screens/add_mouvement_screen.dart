import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/api_service.dart';
import '../models/lot.dart';
import '../theme/terre_et_or_theme.dart';

class AddMouvementScreen extends StatefulWidget {
  final ApiService apiService;

  const AddMouvementScreen({super.key, required this.apiService});

  @override
  State<AddMouvementScreen> createState() => _AddMouvementScreenState();
}

class _AddMouvementScreenState extends State<AddMouvementScreen> {
  List<Lot> lots = [];
  int? selectedLotId;

  // 🔥 CLIENTS
  List<dynamic> clients = [];
  int? selectedClientId;

  String selectedType = "VENTE";
  String selectedProduct = "ANIMAUX";

  final TextEditingController quantiteController = TextEditingController();
  final TextEditingController prixController = TextEditingController();
  final TextEditingController stillbornController = TextEditingController(text: '0');
  final TextEditingController birthNoteController = TextEditingController();
  final TextEditingController birthLotNameController = TextEditingController();
  String birthProductionType = 'CHAIR';
  final TextEditingController traysController = TextEditingController(text: '0');
  final TextEditingController extraEggsController = TextEditingController(text: '0');
  final TextEditingController totalPriceController = TextEditingController();
  int? eggStockAvailable;
  bool eggOriginsComplete = false;
  bool eggStockLoading = false;

  DateTime selectedDate = DateTime.now();

  bool isLoading = true;
  bool isSubmitting = false;

  final List<String> types = [
    "VENTE",
    "MORTALITE",
    "DON",
    "VOL",
    "NAISSANCE",
  ];

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
    if (total == null || stillborn == null || stillborn < 0 ||
        total <= stillborn) {
      return null;
    }
    return total - stillborn;
  }

  // ================= FETCH DATA =================
  Future<void> fetchData() async {
    try {
      final lotsResult = await widget.apiService.getLots();
      final clientsResult = await widget.apiService.getClients();

      final parsedLots =
          (lotsResult as List).map((json) => Lot.fromJson(json)).toList();

      if (!mounted) return;

      setState(() {
        lots = parsedLots;
        clients = clientsResult as List<dynamic>;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      showMessage("Erreur chargement données");
    }
  }

  // ================= GET LOT =================
  List<Lot> get selectableLots => selectedType == 'VENTE' &&
          selectedProduct == 'OEUFS'
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
      if (!mounted || selectedLotId != lotId || selectedProduct != 'OEUFS') return;
      setState(() {
        eggStockAvailable = (stock['stock_global'] as num).toInt();
        eggOriginsComplete = stock['origines_completes'] == true;
        eggStockLoading = false;
      });
    } catch (_) {
      if (!mounted || selectedLotId != lotId || selectedProduct != 'OEUFS') return;
      setState(() => eggStockLoading = false);
    }
  }

  // ================= MESSAGE =================
  void showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ================= CREATE CLIENT =================
  Future<void> showCreateClientDialog() async {
    final nomController = TextEditingController();
    final telController = TextEditingController();
    final villeController = TextEditingController();
    var pays = AppSettings.instance.countryCode;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(context.tr('new_customer')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomController,
                  decoration: InputDecoration(labelText: context.tr('name')),
                ),
                TextField(
                  controller: telController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: context.tr('phone')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: pays.isEmpty ? null : pays,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText:
                        '${context.tr('country')} (${context.tr('optional')})',
                  ),
                  items: AppSettings.sortedCountries(
                    AppSettings.instance.languageCode,
                  )
                      .map(
                        (country) => DropdownMenuItem<String>(
                          value: country.code,
                          child: Text(
                            country.label(AppSettings.instance.languageCode),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => pays = value ?? '');
                  },
                ),
                TextField(
                  controller: villeController,
                  decoration: InputDecoration(
                    labelText:
                        '${context.tr('city')} (${context.tr('optional')})',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text(context.tr('cancel')),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            ElevatedButton(
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
                showMessage("Client créé");
              },
            ),
          ],
        ),
      ),
    );

    nomController.dispose();
    telController.dispose();
    villeController.dispose();
  }

  // ================= SUBMIT =================
  Future<void> submit() async {
    if (isSubmitting) return;

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
          lotId: selectedLotId!, totalBirths: total, stillborn: stillborn,
          newLotName: newLotName, productionType: birthProductionType,
          date: selectedDate, note: birthNoteController.text.trim(),
        );
        if (mounted) {
          setState(() => isSubmitting = false);
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: Text(context.tr('birth_saved')),
              content: Text('${saved['nouveau_lot']['nom']} : '
                  '${saved['nes_vivants']} ${context.tr('birth_live').toLowerCase()} · '
                  '${saved['mort_nes'] ?? stillborn} ${context.tr('birth_stillborn').toLowerCase()}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(context.tr('close')),
                ),
              ],
            ),
          );
          if (mounted) Navigator.pop(context, true);
        }
      } catch (error) {
        if (mounted) showMessage(error.toString().replaceFirst('Exception: ', ''));
      } finally {
        if (mounted) setState(() => isSubmitting = false);
      }
      return;
    }

    if (selectedType == "VENTE" && selectedProduct == "OEUFS") {
      final trays = int.tryParse(traysController.text.trim());
      final extra = int.tryParse(extraEggsController.text.trim());
      if (trays == null || trays < 0 || extra == null || extra < 0 ||
          extra >= 30 || trays * 30 + extra <= 0) {
        showMessage(context.tr('sale_invalid_quantity'));
        return;
      }
      final price = totalPriceController.text.trim().replaceAll(',', '.');
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
        showMessage('${context.tr('sale_stock_insufficient')} : '
            '$eggStockAvailable ${context.tr('egg_eggs_short')}');
        return;
      }
      setState(() => isSubmitting = true);
      try {
        await widget.apiService.createMixedEggSale(
          lotId: selectedLotId!, clientId: selectedClientId!,
          fullTrays: trays, extraEggs: extra,
          totalPrice: price, date: selectedDate,
        );
        if (mounted) Navigator.pop(context, true);
      } catch (error) {
        if (mounted) showMessage(error.toString().replaceFirst('Exception: ', ''));
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
    final prix = double.tryParse(prixController.text.trim());

    if (quantite == null || prix == null) {
      showMessage("Valeurs invalides");
      return;
    }

    if (quantite <= 0) {
      showMessage("Quantité doit être > 0");
      return;
    }

    if (prix <= 0) {
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
        date: selectedDate,
        clientId: selectedClientId,
      );

      if (!mounted) return;

      if (success) {
        Navigator.pop(context, true);
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return AbsorbPointer(
      absorbing: isSubmitting,
      child: Theme(
        data: terreEtOrTheme(context),
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.tr('add_movement')),
          ),
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
                        DropdownButtonFormField<String>(
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
                              selectedLotId = null;
                              eggStockAvailable = null;
                              eggOriginsComplete = false;
                            });
                          },
                          decoration: InputDecoration(
                            labelText: context.tr('movement_type'),
                            border: OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 16),

                        if (selectedType == 'VENTE') ...[
                          DropdownButtonFormField<String>(
                            key: const Key('saleProductDropdown'),
                            value: selectedProduct,
                            decoration: InputDecoration(
                              labelText: context.tr('sale_product'),
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem(value: 'ANIMAUX',
                                  child: Text(context.tr('sale_animals'))),
                              DropdownMenuItem(value: 'OEUFS',
                                  child: Text(context.tr('sale_eggs'))),
                            ],
                            onChanged: (value) {
                              setState(() {
                                selectedProduct = value ?? 'ANIMAUX';
                                selectedLotId = null;
                                eggStockAvailable = null;
                                eggOriginsComplete = false;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        // LOT
                        DropdownButtonFormField<int>(
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
                            if (value != null && selectedType == 'VENTE' &&
                                selectedProduct == 'OEUFS') {
                              loadEggStock(value);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: selectedType == 'NAISSANCE'
                                ? context.tr('birth_parent') : context.tr('batch'),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (selectedType == 'NAISSANCE' && selectedLot != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${context.tr('birth_species')} : ${selectedLot!.especeNom ?? ''}',
                              key: const Key('birthSpecies'),
                            ),
                          ),
                        if (selectedType == 'VENTE' && selectedProduct == 'OEUFS' &&
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
                                    child: DropdownButtonFormField<int>(
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
                                      decoration: InputDecoration(
                                        labelText: context.tr('customer'),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle,
                                        color: Colors.green),
                                    onPressed: showCreateClientDialog,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),

                        // STOCK
                        if (selectedLot != null && selectedType == 'VENTE' &&
                            selectedProduct == 'OEUFS')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: eggStockLoading
                                ? const CircularProgressIndicator()
                                : eggStockAvailable == null
                                    ? TextButton(
                                        key: const Key('eggStockRetry'),
                                        onPressed: () => loadEggStock(selectedLotId!),
                                        child: Text(context.tr('sale_stock_retry')),
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${context.tr('sale_stock_eggs')} : '
                                            '$eggStockAvailable ${context.tr('egg_eggs_short')} · '
                                            '${eggStockAvailable! ~/ 30} ${context.tr('egg_trays_short')} + '
                                            '${eggStockAvailable! % 30} ${context.tr('egg_eggs_short')}',
                                            key: const Key('eggSaleStock'),
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          if (!eggOriginsComplete)
                                            Text(
                                              context.tr('sale_origins_incomplete'),
                                              key: const Key('eggSaleOriginsIncomplete'),
                                            ),
                                        ],
                                      ),
                          )
                        else if (selectedLot != null && selectedType != 'NAISSANCE')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Stock disponible: ${selectedLot!.stock}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),

                        const SizedBox(height: 16),

                        // DATE
                        TerreEtOrDateTile(
                          label:
                              "${context.tr('date')} : ${selectedDate.toLocal().toString().split(' ')[0]}",
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );

                            if (picked != null) {
                              setState(() {
                                if (birthLotNameController.text ==
                                    defaultBirthLotName(selectedDate)) {
                                  birthLotNameController.text =
                                      defaultBirthLotName(picked);
                                }
                                selectedDate = picked;
                              });
                            }
                          },
                        ),

                        const SizedBox(height: 16),

                        // QUANTITE
                        if (selectedType == 'VENTE' && selectedProduct == 'OEUFS') ...[
                          TextField(
                            key: const Key('eggSaleTrays'),
                            controller: traysController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('egg_full_trays'),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('eggSaleExtra'),
                            controller: extraEggsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('sale_extra_eggs'),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${context.tr('sale_total_eggs')} : '
                            '${((int.tryParse(traysController.text) ?? 0) * 30) + (int.tryParse(extraEggsController.text) ?? 0)} '
                            '${context.tr('egg_eggs_short')}',
                            key: const Key('eggSaleTotalEggs'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('eggSaleTotalPrice'),
                            controller: totalPriceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: '${context.tr('sale_total_price')} '
                                  '(${AppSettings.instance.currency.symbol})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ] else if (selectedType == 'NAISSANCE') ...[
                          TextField(
                            key: const Key('birthTotal'),
                            controller: quantiteController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('birth_total'),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('birthStillborn'),
                            controller: stillbornController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('birth_stillborn'),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${context.tr('birth_live')} : '
                            '${birthLivePreview ?? '—'}',
                            key: const Key('birthCalculatedLive'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('birthNewLotName'),
                            controller: birthLotNameController,
                            decoration: InputDecoration(
                              labelText: context.tr('birth_new_lot'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            key: const Key('birthProductionType'),
                            initialValue: birthProductionType,
                            decoration: InputDecoration(
                              labelText: context.tr('birth_new_lot_type'),
                              border: const OutlineInputBorder(),
                            ),
                            items: ['CHAIR', 'OEUFS', 'REPRODUCTION', 'AUTRE']
                                .map((type) => DropdownMenuItem<String>(
                                      value: type,
                                      child: Text(context.tr({
                                        'CHAIR': 'production_type_meat',
                                        'OEUFS': 'production_type_eggs',
                                        'REPRODUCTION': 'production_type_reproduction',
                                        'AUTRE': 'production_type_other',
                                      }[type]!)),
                                    ))
                                .toList(),
                            onChanged: (value) => setState(() =>
                                birthProductionType = value ?? 'CHAIR'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('birthNote'),
                            controller: birthNoteController,
                            decoration: InputDecoration(
                              labelText: context.tr('birth_note'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ] else ...[
                          TextField(
                            key: const Key('animalSaleQuantity'),
                            controller: quantiteController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('quantity'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('animalSalePrice'),
                            controller: prixController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '${context.tr('unit_price_auto')} '
                                  '(${AppSettings.instance.currency.symbol})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // BOUTON
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const Key('saveMovement'),
                            onPressed: isSubmitting ? null : submit,
                            child: isSubmitting
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
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
