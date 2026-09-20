import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/api_service.dart';

class AddAchatScreen extends StatefulWidget {
  final ApiService apiService;

  const AddAchatScreen({super.key, required this.apiService});

  @override
  State<AddAchatScreen> createState() => _AddAchatScreenState();
}

class _AddAchatScreenState extends State<AddAchatScreen> {
  static const speciesCatalog = <String>[
    'Poulet',
    'Dinde',
    'Canard',
    'Pintade',
    'Porc',
    'Bovin',
    'Mouton',
    'Chèvre',
    'Lapin',
    'Poisson',
    'Œufs',
  ];

  final _formKey = GlobalKey<FormState>();

  final TextEditingController nomLotController = TextEditingController();
  final TextEditingController quantiteController = TextEditingController();
  final TextEditingController prixTotalController = TextEditingController();
  final TextEditingController prixUnitaireController = TextEditingController();

  DateTime selectedDate = DateTime.now();

  List especes = [];
  int? selectedEspece;

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
      final existingNames = data
          .map((item) => item['nom'].toString().toLowerCase())
          .toSet();
      final missing = speciesCatalog
          .where((name) => !existingNames.contains(name.toLowerCase()))
          .toList();

      if (missing.isNotEmpty) {
        await Future.wait(
          missing.map((name) async {
            try {
              await widget.apiService.createEspece(name);
            } catch (_) {
              // Une autre requête peut avoir créé l'espèce entre-temps.
            }
          }),
        );
        data = await widget.apiService.getEspeces();
      }

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
      'Œufs': 'Eggs',
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ================= SUBMIT =================
  Future<void> submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedEspece == null) {
      showMessage(context.tr('species_required'));
      return;
    }

    final quantite = int.tryParse(quantiteController.text.trim());
    final prixTotal = double.tryParse(prixTotalController.text.trim());
    final prixUnitaire =
        double.tryParse(prixUnitaireController.text.trim());

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
  date: selectedDate,
);

      if (!mounted) return;

      if (success) {
        showMessage(context.tr('purchase_created'));
        Navigator.pop(context, true);
      } else {
        showMessage("Erreur création ❌");
      }
    } catch (e) {
      showMessage(e.toString()); // 🔥 IMPORTANT
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('new_purchase')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // ================= NOM LOT =================
              TextFormField(
                controller: nomLotController,
                decoration: InputDecoration(
                  labelText: context.tr('lot_name'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? context.tr('required') : null,
              ),

              const SizedBox(height: 16),

              Autocomplete<Map<String, dynamic>>(
                displayStringForOption: (option) =>
                    speciesLabel(option['nom'].toString()),
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  final options = especes.cast<Map<String, dynamic>>();
                  if (query.isEmpty) return options;
                  return options.where(
                    (item) => speciesLabel(item['nom'].toString())
                        .toLowerCase()
                        .contains(query),
                  );
                },
                onSelected: (option) {
                  setState(() => selectedEspece = option['id'] as int);
                },
                fieldViewBuilder: (
                  context,
                  textEditingController,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    onChanged: (_) => setState(() => selectedEspece = null),
                    decoration: InputDecoration(
                      labelText: context.tr('choose_species'),
                      hintText: context.tr('search_species'),
                      prefixIcon: const Icon(Icons.pets_outlined),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (_) => selectedEspece == null
                        ? context.tr('species_required')
                        : null,
                  );
                },
              ),

              const SizedBox(height: 16),

              // ================= QUANTITE =================
              TextFormField(
                controller: quantiteController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('quantity'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => calculatePrixUnitaire(),
                validator: (value) =>
                    value == null || value.isEmpty ? context.tr('required') : null,
              ),

              const SizedBox(height: 16),

              // ================= PRIX TOTAL =================
              TextFormField(
                controller: prixTotalController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${context.tr('total_price')} (${AppSettings.instance.currency.symbol})',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => calculatePrixUnitaire(),
                validator: (value) =>
                    value == null || value.isEmpty ? context.tr('required') : null,
              ),

              const SizedBox(height: 16),

              // ================= PRIX UNITAIRE =================
              TextFormField(
                controller: prixUnitaireController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: '${context.tr('unit_price_auto')} (${AppSettings.instance.currency.symbol})',
                  border: const OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // ================= DATE =================
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  "${context.tr('date')} : ${selectedDate.toLocal().toString().split(' ')[0]}",
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );

                  if (picked != null) {
                    setState(() => selectedDate = picked);
                  }
                },
              ),

              const SizedBox(height: 20),

              // ================= BOUTON =================
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : submit,
                  child: isSubmitting
                      ? const CircularProgressIndicator(
                          color: Colors.white)
                      : Text(context.tr('create_lot')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
