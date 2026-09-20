import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';

class LotDetailScreen extends StatefulWidget {
  final ApiService apiService;
  final int lotId;

  const LotDetailScreen({
    super.key,
    required this.apiService,
    required this.lotId,
  });

  @override
  State<LotDetailScreen> createState() => _LotDetailScreenState();
}

class _LotDetailScreenState extends State<LotDetailScreen> {

  Map<String, dynamic>? lot;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchLot();
  }

  Future<void> fetchLot() async {
    try {
      final result = await widget.apiService.getLotDetail(widget.lotId);

      if (!mounted) return;

      setState(() {
        lot = result;
        isLoading = false;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<bool> confirmDelete() async {
    return await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(context.tr('confirmation')),
            content: Text(context.tr('delete_item')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr('delete')),
              ),
            ],
          ),
        ) ??
        false;
  }

  void showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (lot == null) {
      return const Scaffold(
        body: Center(child: Text("Erreur chargement lot")),
      );
    }

    final mouvements = List.from(lot!["mouvements"] ?? [])
        .where((m) => m["type_mouvement"] != "ACHAT")
        .toList();

    final depenses = List.from(lot!["depenses"] ?? []);
    final achats = lot!["achats"] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(lot!["nom"].toString()),
      ),

      body: RefreshIndicator(
        onRefresh: fetchLot,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ================= INFOS =================
              Text(
                lot!["nom"].toString(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text("${context.tr('species')} : ${lot!["espece_nom"] ?? ""}"),
              Text("${context.tr('start_date')} : ${lot!["date_debut"] ?? ""}"),
              Text("${context.tr('created_on')} : ${lot!["date_creation"] ?? ""}"),
              Text(
                "Stock actuel : ${lot!["stock"] ?? 0}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 24),

              // ================= ACHATS (1er) =================
              const Text(
                "Achats",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              if (achats.isEmpty)
                Text(context.tr('no_purchase')),

              ...achats.map<Widget>((a) {
  final int? achatId = a["id"];

  return Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: ListTile(
      leading: const Icon(Icons.shopping_bag, color: Colors.blue),

      title: Text(context.tr('purchase')),

      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${context.tr('quantity')}: ${a["quantite"]}"),

          if (a["prix_unitaire"] != null)
            Text(
              "PU: ${AppSettings.instance.formatMoney(a["prix_unitaire"], decimals: 2)}",
              style: const TextStyle(
                fontSize: 12,
                color: Colors.blue,
              ),
            ),

          if (a["prix_total"] != null)
            Text(
              "Total: ${AppSettings.instance.formatMoney(a["prix_total"], decimals: 2)}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
        ],
      ),

      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(a["date"] ?? ""),

          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () async {
              final confirm = await confirmDelete();
              if (!confirm) return;

              if (achatId == null) {
                showMessage("ID achat manquant");
                return;
              }

              try {
                final success = await widget.apiService.deleteAchat(achatId);

                if (success && mounted) {
                  showMessage("Lot supprimé ✅");

                  // 🔥 IMPORTANT : on revient en arrière car le lot n'existe plus
                  Navigator.pop(context, true);
                }

              } catch (e) {
                showMessage("Erreur suppression achat");
              }
            },
          ),
        ],
      ),
    ),
  );
}).toList(),

              // ================= MOUVEMENTS (2e) =================
              const Text(
                "Mouvements",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              if (mouvements.isEmpty)
                Text(context.tr('no_movement')),

              ...mouvements.map<Widget>((m) {
                final int? id = m["id"];

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.swap_vert),
                    title: Text(m["type_mouvement"] ?? ""),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${context.tr('quantity')}: ${m["quantite"]}"),

                        if (m["prix_unitaire"] != null)
                          Text(
                            "PU: ${AppSettings.instance.formatMoney(m["prix_unitaire"], decimals: 2)}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(m["date"] ?? ""),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await confirmDelete();
                            if (!confirm) return;

                            if (id == null) return;

                            final success = await widget.apiService.deleteMouvement(id);

                            if (success) {
                              showMessage("Supprimé ✅");
                              fetchLot();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),

              const SizedBox(height: 24),

              // ================= DEPENSES (3e) =================
              const Text(
                "Dépenses",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              if (depenses.isEmpty)
                Text(context.tr('no_expense')),

              ...depenses.map<Widget>((d) {
                final int? id = d["id"];

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.money_off),
                    title: Text(d["categorie_nom"] ?? "Autre"),
                    subtitle: Text("${context.tr('amount')}: ${d["montant"]}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(d["date"] ?? ""),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await confirmDelete();
                            if (!confirm) return;

                            if (id == null) return;

                            final success = await widget.apiService.deleteDepense(id);

                            if (success) {
                              showMessage("Supprimé ✅");
                              fetchLot();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
