import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/api_service.dart';
import '../theme/terre_et_or_theme.dart';

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

    return Theme(
      data: terreEtOrTheme(context),
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.tr('add_expense')),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TerreEtOrHeader(
                icon: Icons.account_balance_wallet_outlined,
                title: context.tr('add_expense'),
                subtitle: AppSettings.instance.languageCode == 'en'
                    ? 'Record an expense linked to a batch'
                    : 'Enregistrez une charge liée à un lot',
              ),
              TerreEtOrPanel(
                child: Column(
                  children: [

              // ================= LOT =================
              DropdownButtonFormField<int>(
                value: selectedLotId,
                hint: Text(context.tr('choose_batch')),
                items: lots.map<DropdownMenuItem<int>>((lot) {
                  return DropdownMenuItem(
                    value: lot["id"],
                    child: Text(lot["nom"]),
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

              // ================= CATEGORIE =================
              DropdownButtonFormField<int>(
                value: selectedCategorieId,
                hint: Text(context.tr('choose_category')),
                items: categories.map<DropdownMenuItem<int>>((c) {
                  return DropdownMenuItem(
                    value: c["id"],
                    child: Text(c["nom"]),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedCategorieId = value);
                },
                decoration: InputDecoration(
                  labelText: context.tr('category'),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // ================= DATE =================
              TerreEtOrDateTile(
                label: "${context.tr('date')} : ${selectedDate.toLocal().toString().split(' ')[0]}",
                onTap: pickDate,
              ),

              const SizedBox(height: 16),

              // ================= MONTANT =================
              TextField(
                controller: montantController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${context.tr('amount')} (${AppSettings.instance.currency.symbol})',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // ================= NOTE =================
              TextField(
                controller: noteController,
                decoration: InputDecoration(
                  labelText: context.tr('optional_note'),
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
                      : Text(context.tr('save')),
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
