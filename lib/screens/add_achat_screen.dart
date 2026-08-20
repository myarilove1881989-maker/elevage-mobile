import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AddAchatScreen extends StatefulWidget {
  final ApiService apiService;

  const AddAchatScreen({super.key, required this.apiService});

  @override
  State<AddAchatScreen> createState() => _AddAchatScreenState();
}

class _AddAchatScreenState extends State<AddAchatScreen> {
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
    final data = await widget.apiService.getEspeces();

    if (!mounted) return;

    setState(() {
      especes = data;
      isLoading = false;
    });
  } catch (e) {
    if (!mounted) return;

    setState(() => isLoading = false);
    showMessage("Erreur chargement espèces");
  }
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

  // ================= CREATE ESPECE =================
  Future<void> openCreateEspeceDialog() async {
    final TextEditingController controller = TextEditingController();

    final result = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Nouvelle espèce"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Nom de l'espèce",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler"),
            ),
            ElevatedButton(
              onPressed: () async {
                final nom = controller.text.trim();

                if (nom.isEmpty) return;

                final espece =
                    await widget.apiService.createEspece(nom);

                Navigator.pop(context, espece);
              },
              child: const Text("Créer"),
            ),
          ],
        );
      },
    );

                if (result != null) {
                final newId = result["id"];

                    await loadEspeces();

                if (!mounted) return;

                setState(() {
                  selectedEspece = newId;
  });

                showMessage("Espèce ajoutée ✅");
}
  }

  // ================= SUBMIT =================
  Future<void> submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedEspece == null) {
      showMessage("Choisir une espèce");
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
        showMessage("Lot créé avec achat ✅");
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
        title: const Text("Nouvel Achat (Création Lot)"),
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
                decoration: const InputDecoration(
                  labelText: "Nom du lot",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? "Champ requis" : null,
              ),

              const SizedBox(height: 16),

              // ================= ESPECE + BOUTON + =================
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: selectedEspece,
                      hint: const Text("Choisir une espèce"),
                      items:
                          especes.map<DropdownMenuItem<int>>((e) {
                        return DropdownMenuItem<int>(
                          value: e["id"],
                          child: Text(e["nom"]),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedEspece = value);
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null ? "Champ requis" : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: openCreateEspeceDialog,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ================= QUANTITE =================
              TextFormField(
                controller: quantiteController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Quantité",
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => calculatePrixUnitaire(),
                validator: (value) =>
                    value == null || value.isEmpty ? "Champ requis" : null,
              ),

              const SizedBox(height: 16),

              // ================= PRIX TOTAL =================
              TextFormField(
                controller: prixTotalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Prix total",
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => calculatePrixUnitaire(),
                validator: (value) =>
                    value == null || value.isEmpty ? "Champ requis" : null,
              ),

              const SizedBox(height: 16),

              // ================= PRIX UNITAIRE =================
              TextFormField(
                controller: prixUnitaireController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Prix unitaire (auto)",
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
                      : const Text("Créer le lot"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}