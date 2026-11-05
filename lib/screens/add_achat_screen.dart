import '../widgets/v2_components.dart';
import 'package:flutter/material.dart';
import '../widgets/operation_status.dart';
import '../l10n/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/api_service.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/terrain_entry_gate.dart';

class AddAchatScreen extends StatelessWidget {
  const AddAchatScreen({super.key,required this.apiService});
  final ApiService apiService;
  @override
  Widget build(BuildContext context)=>TerrainEntryGate(api:apiService,actions:const {'purchases.create'},
    ownerBuilder:(_)=>_ClassicAchatScreen(apiService:apiService,readOnly:true),
    builder:(_)=>_ClassicAchatScreen(apiService:apiService));
}

class _ClassicAchatScreen extends StatefulWidget {
  final ApiService apiService;

  const _ClassicAchatScreen({required this.apiService,this.readOnly=false});
  final bool readOnly;

  @override
  State<_ClassicAchatScreen> createState() => _AddAchatScreenState();
}

class _AddAchatScreenState extends State<_ClassicAchatScreen> {

  final _formKey = GlobalKey<FormState>();

  final TextEditingController nomLotController = TextEditingController();
  final TextEditingController quantiteController = TextEditingController();
  final TextEditingController prixTotalController = TextEditingController();
  final TextEditingController prixUnitaireController = TextEditingController();

  DateTime selectedDate = DateTime.now();

  List especes = [];
  int? selectedEspece;
  String selectedProductionType = 'CHAIR';
  String selectedProductionStatus = 'ELEVAGE';
  DateTime? layingStartDate;

  bool isLoading = true;
  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    loadEspeces();
  }

  // ================= LOAD ESPECES =================
  Future<void> loadEspeces() async {
    setState(() => isLoading = true);

    try {
      var data = await widget.apiService.getEspeces();
      // Consultation never creates species. Only server-provided references are used.
      if (!mounted) return;
      setState(() {
        especes = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      showMessage(context.tr('loading_species_error'));
    }
  }

  String speciesLabel(String name) {
    if (AppSettings.instance.languageCode != 'en') return name;
    const englishNames = <String, String>{
      'Poulet': 'Chicken',
      'Dinde': 'Turkey',
      'Canard': 'Duck',
      'Pintade': 'Guinea fowl',
      'Porc': 'Pig',
      'Bovin': 'Cattle',
      'Mouton': 'Sheep',
      'Chèvre': 'Goat',
      'Lapin': 'Rabbit',
      'Poisson': 'Fish',
    };
    return englishNames[name] ?? name;
  }

  // ================= CALCUL PRIX =================
  void calculatePrixUnitaire() {
    final q = int.tryParse(quantiteController.text.trim());
    final total = double.tryParse(prixTotalController.text.trim());

    if (q != null && q > 0 && total != null && total > 0) {
      final pu = total / q;
      prixUnitaireController.text = pu.toStringAsFixed(2);
    } else {
      prixUnitaireController.clear();
    }
  }

  // ================= MESSAGE =================
  void showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ================= SUBMIT =================
  Future<void> submit() async {
    if(widget.readOnly || !await TerrainEntryGate.allowClassic(context,widget.apiService,{'purchases.create'}) || !mounted) return;
    if (!_formKey.currentState!.validate()) return;

    if (selectedEspece == null) {
      showMessage(context.tr('species_required'));
      return;
    }

    final quantite = int.tryParse(quantiteController.text.trim());
    final prixTotal = double.tryParse(prixTotalController.text.trim());
    final prixUnitaire = double.tryParse(prixUnitaireController.text.trim());

    if (quantite == null || quantite <= 0) {
      showMessage("Quantité invalide");
      return;
    }

    if (prixTotal == null || prixTotal <= 0) {
      showMessage("Prix total invalide");
      return;
    }

    if (prixUnitaire == null || prixUnitaire <= 0) {
      showMessage("Prix unitaire invalide");
      return;
    }

    setState(() => isSubmitting = true);

    try {
      // 🔥 2. créer l'achat
      final success = await widget.apiService.createAchat(
        nomLot: nomLotController.text.trim(),
        especeId: selectedEspece!,
        quantite: quantite,
        prixTotal: prixTotal,
        prixUnitaire: prixUnitaire,
        date: DateTime.now(),
        typeProduction: selectedProductionType,
        statutProduction: selectedProductionStatus,
        dateDebutPonte: layingStartDate,
      );

      if (!mounted) return;

      if (success) {
        showMessage(widget.apiService.operationFeedback(context.tr('purchase_created')));
        if(!(widget.apiService.hasUnifiedOfflineSession && widget.apiService.lastOperationMessage!=null))v2Confirmed(context,message:context.tr('purchase_created'));
      } else {
        showMessage("Erreur création ❌");
      }
    } catch (e) {
      if (mounted) { showMessage(unconfirmedOperationMessage); }
    }

    if (!mounted) return;
    setState(() => isSubmitting = false);
  }

  @override
  void dispose() {
    nomLotController.dispose();
    quantiteController.dispose();
    prixTotalController.dispose();
    prixUnitaireController.dispose();
    super.dispose();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return V2Scaffold(protectDraft:true,busy:isSubmitting,body: Center(child: CircularProgressIndicator()));
    }

    return Theme(
      data: terreEtOrTheme(context),
      child: V2Scaffold(protectDraft:true,busy:isSubmitting,
        appBar: V2AppBar(title: Text(context.tr('new_purchase'))),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TerreEtOrHeader(
                  icon: Icons.shopping_bag_outlined,
                  title: context.tr('new_purchase'),
                  subtitle: AppSettings.instance.languageCode == 'en'
                      ? 'Create a batch and record its initial purchase'
                      : 'Créez un lot et enregistrez son achat initial',
                ),
                TerreEtOrPanel(
                  child: Column(
                    children: [
                      // ================= NOM LOT =================
                      V2Field(child:TextFormField(
                        controller: nomLotController,
                        decoration: V2InputDecoration(
                          labelText: context.tr('lot_name'),prefixIcon:const Icon(Icons.inventory_2_outlined),),
                        validator: (value) => value == null || value.isEmpty
                            ? context.tr('required')
                            : null,
                      )),

                      const SizedBox(height: 16),

                      Autocomplete<Map<String, dynamic>>(
                        displayStringForOption: (option) =>
                            speciesLabel(option['nom'].toString()),
                        optionsBuilder: (textEditingValue) {
                          final query = textEditingValue.text
                              .trim()
                              .toLowerCase();
                          final options = especes.cast<Map<String, dynamic>>();
                          if (query.isEmpty) return options;
                          return options.where(
                            (item) => speciesLabel(
                              item['nom'].toString(),
                            ).toLowerCase().contains(query),
                          );
                        },
                        onSelected: (option) {
                          setState(() => selectedEspece = option['id'] as int);
                        },
                        fieldViewBuilder:
                            (
                              context,
                              textEditingController,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              return V2Field(child:TextFormField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                onChanged: (_) =>
                                    setState(() => selectedEspece = null),
                                decoration: V2InputDecoration(
                                  labelText: context.tr('choose_species'),
                                  hintText: context.tr('search_species'),
                                  prefixIcon: const Icon(Icons.pets_outlined),
                                  suffixIcon: const Icon(Icons.arrow_drop_down),),
                                validator: (_) => selectedEspece == null
                                    ? context.tr('species_required')
                                    : null,
                              ));
                            },
                      ),

                      const SizedBox(height: 16),

                      V2Field(child:DropdownButtonFormField<String>(

                        isExpanded: true,

                        initialValue: selectedProductionType,
                        decoration: const V2InputDecoration(
                          labelText: 'Type de production',
                          prefixIcon: Icon(Icons.category_outlined),),
                        items: const [
                          DropdownMenuItem(
                            value: 'CHAIR',
                            child: Text('Élevage de chair'),
                          ),
                          DropdownMenuItem(
                            value: 'OEUFS',
                            child: Text('Production d’œufs'),
                          ),
                          DropdownMenuItem(
                            value: 'REPRODUCTION',
                            child: Text('Reproduction'),
                          ),
                          DropdownMenuItem(
                            value: 'AUTRE',
                            child: Text('Autre'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            selectedProductionType = value;
                            selectedProductionStatus = value == 'OEUFS'
                                ? 'PONTE'
                                : 'ELEVAGE';
                            if (value != 'OEUFS') layingStartDate = null;
                          });
                        },
                      )),

                      if (selectedProductionType == 'OEUFS') ...[
                        const SizedBox(height: 16),
                        V2Field(child:DropdownButtonFormField<String>(

                          isExpanded: true,

                          initialValue: selectedProductionStatus,
                          decoration: const V2InputDecoration(
                            labelText: 'Statut du lot',),
                          items: const [
                            DropdownMenuItem(
                              value: 'ELEVAGE',
                              child: Text('Élevage'),
                            ),
                            DropdownMenuItem(
                              value: 'PONTE',
                              child: Text('Ponte'),
                            ),
                            DropdownMenuItem(
                              value: 'REFORME',
                              child: Text('Réforme'),
                            ),
                            DropdownMenuItem(
                              value: 'TERMINE',
                              child: Text('Terminé'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => selectedProductionStatus = value);
                            }
                          },
                        )),
                        const SizedBox(height: 16),
                        TerreEtOrDateTile(
                          label: layingStartDate == null
                              ? 'Date de début de ponte (facultative)'
                              : 'Début de ponte : ${v2Day(layingStartDate!.toIso8601String())}',
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: layingStartDate ?? selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => layingStartDate = picked);
                            }
                          },
                        ),
                      ],

                      const SizedBox(height: 16),

                      // ================= QUANTITE =================
                      V2Field(child:TextFormField(
                        controller: quantiteController,
                        keyboardType: TextInputType.number,
                        decoration: V2InputDecoration(
                          labelText: context.tr('quantity'),prefixIcon:const Icon(Icons.numbers),),
                        onChanged: (_) => calculatePrixUnitaire(),
                        validator: (value) => value == null || value.isEmpty
                            ? context.tr('required')
                            : null,
                      )),

                      const SizedBox(height: 16),

                      // ================= PRIX TOTAL =================
                      V2Field(child:TextFormField(
                        controller: prixTotalController,
                        keyboardType: TextInputType.number,
                        decoration: V2InputDecoration(
                          labelText:
                              '${context.tr('total_price')} (${AppSettings.instance.currency.symbol})',),
                        onChanged: (_) => calculatePrixUnitaire(),
                        validator: (value) => value == null || value.isEmpty
                            ? context.tr('required')
                            : null,
                      )),

                      const SizedBox(height: 16),

                      // ================= PRIX UNITAIRE =================
                      V2Field(child:TextFormField(
                        controller: prixUnitaireController,
                        readOnly: true,
                        decoration: V2InputDecoration(
                          labelText:
                              '${context.tr('unit_price_auto')} (${AppSettings.instance.currency.symbol})',),
                      )),

                      const SizedBox(height: 16),

                      // ================= DATE =================
                      TerreEtOrDateTile(
                        label:
                            "${context.tr('date')} : ${v2Day(selectedDate.toLocal().toIso8601String())}",
                        onTap: null,
                      ),

                      const SizedBox(height: 20),

                      // ================= BOUTON =================
                      SizedBox(
                        width: double.infinity,
                        child: widget.readOnly ? const SizedBox.shrink() : ElevatedButton(
                          onPressed: isSubmitting ? null : submit,
                          child: isSubmitting
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(context.tr('create_lot')),
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
    );
  }
}
