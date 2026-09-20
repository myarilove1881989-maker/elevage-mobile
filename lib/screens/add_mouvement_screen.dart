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

  final TextEditingController quantiteController = TextEditingController();
  final TextEditingController prixController = TextEditingController();

  DateTime selectedDate = DateTime.now();

  bool isLoading = true;
  bool isSubmitting = false;

  final List<String> types = [
    "VENTE",
    "MORTALITE",
    "DON",
    "VOL",
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
      default:
        return type;
    }
  }

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  // ================= FETCH DATA =================
  Future<void> fetchData() async {
    try {
      final lotsResult = await widget.apiService.getLots();
      final clientsResult = await widget.apiService.getClients();

      final parsedLots = (lotsResult as List)
          .map((json) => Lot.fromJson(json))
          .toList();

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
  Lot? get selectedLot {
    if (selectedLotId == null) return null;
    return lots.firstWhere(
      (lot) => lot.id == selectedLotId,
      orElse: () => lots.first,
    );
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

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(context.tr('new_customer')),
          content: Column(
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
            ],
          ),
          actions: [
            TextButton(
              child: Text(context.tr('cancel')),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: Text(context.tr('add')),
              onPressed: () async {
                if (nomController.text.isEmpty ||
                    telController.text.isEmpty) {
                  showMessage("Tous les champs sont obligatoires");
                  return;
                }

                await widget.apiService.createClient(
                  nomController.text,
                  telController.text,
                );

                Navigator.pop(context);
                await fetchData();

                showMessage("Client créé");
              },
            ),
          ],
        );
      },
    );
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
                      ? 'Record a sale, mortality, donation or theft'
                      : 'Enregistrez une vente, mortalité, un don ou un vol',
                ),
                TerreEtOrPanel(
                  child: Column(
                    children: [

                // TYPE
                DropdownButtonFormField<String>(
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
                    });
                  },
                decoration: InputDecoration(
                    labelText: context.tr('movement_type'),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // LOT
                DropdownButtonFormField<int>(
                  value: selectedLotId,
                  items: lots.map((lot) {
                    return DropdownMenuItem<int>(
                      value: lot.id,
                      child: Text(lot.nom),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedLotId = value);
                  },
                decoration: InputDecoration(
                    labelText: context.tr('batch'),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // 🔥 CLIENT
                if (selectedType == "VENTE")
                  Column(
                    children: [
                      Row(
                        children: [

                          Expanded(
                            child: DropdownButtonFormField<int>(
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
                            icon: const Icon(Icons.add_circle, color: Colors.green),
                            onPressed: showCreateClientDialog,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),

                // STOCK
                if (selectedLot != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Stock disponible: ${selectedLot!.stock}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),

                const SizedBox(height: 16),

                // DATE
                TerreEtOrDateTile(
                  label: "${context.tr('date')} : ${selectedDate.toLocal().toString().split(' ')[0]}",
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

                const SizedBox(height: 16),

                // QUANTITE
                TextField(
                  controller: quantiteController,
                  keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: context.tr('quantity'),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // PRIX
                TextField(
                  controller: prixController,
                  keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: '${context.tr('unit_price_auto')} (${AppSettings.instance.currency.symbol})',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 20),

                // BOUTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : submit,
                    child: isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
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
