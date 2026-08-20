import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AddDepenseScreen extends StatefulWidget {
  final ApiService apiService;

  const AddDepenseScreen({
    super.key,
    required this.apiService,
  });

  @override
  State<AddDepenseScreen> createState() => _AddDepenseScreenState();
}

class _AddDepenseScreenState extends State<AddDepenseScreen> {

  List<dynamic> lots = [];
  List<dynamic> categories = [];

  int? selectedLotId;
  int? selectedCategorieId;

  final TextEditingController montantController = TextEditingController();
  final TextEditingController noteController = TextEditingController();

  DateTime selectedDate = DateTime.now();

  bool isLoading = false;
  bool isInitLoading = true;

  @override
  void initState() {
    super.initState();
    initData();
  }

  // ================= INIT =================
  Future<void> initData() async {
    await Future.wait([
      fetchLots(),
      fetchCategories(),
    ]);

    if (!mounted) return;

    setState(() {
      isInitLoading = false;
    });
  }

  // ================= FETCH LOTS =================
  Future<void> fetchLots() async {
    try {
      final result = await widget.apiService.getLots();
      lots = result;
    } catch (e) {
      debugPrint("❌ Erreur chargement lots");
    }
  }

  // ================= FETCH CATEGORIES =================
  Future<void> fetchCategories() async {
    try {
      final result = await widget.apiService.getCategoriesDepense();
      categories = result;
    } catch (e) {
      debugPrint("❌ ERREUR CATEGORIES: $e");
    }
  }

  // ================= MESSAGE =================
  void showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ================= DATE =================
  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  // ================= SUBMIT =================
  Future<void> submit() async {

    final montant = double.tryParse(montantController.text.trim());

    if (selectedLotId == null) {
      showMessage("Sélectionne un lot");
      return;
    }

    if (selectedCategorieId == null) {
      showMessage("Sélectionne une catégorie");
      return;
    }

    if (montant == null || montant <= 0) {
      showMessage("Montant invalide");
      return;
    }

    setState(() => isLoading = true);

    try {
      final success = await widget.apiService.createDepense(
        lotId: selectedLotId!,
        categorieId: selectedCategorieId!,
        montant: montant,
        date: selectedDate,
        note: noteController.text.trim(),
      );

      if (!mounted) return;

      if (success) {
        Navigator.pop(context, true);
      } else {
        showMessage("Erreur enregistrement");
      }

    } catch (e) {
      showMessage("Erreur serveur");
    }

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    montantController.dispose();
    noteController.dispose();
    super.dispose();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {

    if (isInitLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ajouter dépense"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [

              // ================= LOT =================
              DropdownButtonFormField<int>(
                value: selectedLotId,
                hint: const Text("Choisir un lot"),
                items: lots.map<DropdownMenuItem<int>>((lot) {
                  return DropdownMenuItem(
                    value: lot["id"],
                    child: Text(lot["nom"]),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedLotId = value);
                },
                decoration: const InputDecoration(
                  labelText: "Lot",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // ================= CATEGORIE =================
              DropdownButtonFormField<int>(
                value: selectedCategorieId,
                hint: const Text("Choisir une catégorie"),
                items: categories.map<DropdownMenuItem<int>>((c) {
                  return DropdownMenuItem(
                    value: c["id"],
                    child: Text(c["nom"]),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedCategorieId = value);
                },
                decoration: const InputDecoration(
                  labelText: "Catégorie",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // ================= DATE =================
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  "Date : ${selectedDate.toLocal().toString().split(' ')[0]}",
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: pickDate,
              ),

              const SizedBox(height: 16),

              // ================= MONTANT =================
              TextField(
                controller: montantController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Montant",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // ================= NOTE =================
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: "Note (optionnel)",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 20),

              // ================= BOUTON =================
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : submit,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Enregistrer"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}