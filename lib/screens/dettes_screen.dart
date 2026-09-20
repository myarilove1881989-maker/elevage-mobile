import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../models/dette_client.dart';

class DettesScreen extends StatefulWidget {
  final ApiService apiService;

  const DettesScreen({super.key, required this.apiService});

  @override
  State<DettesScreen> createState() => _DettesScreenState();
}

class _DettesScreenState extends State<DettesScreen> {
  List<DetteClient> clients = [];
  bool isLoading = true;

  String selectedFilter = "ALL";
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final data = await widget.apiService.getDettesClients();

      // 🔥 TRI : plus gros débiteurs en haut
      data.sort((a, b) => b.reste.compareTo(a.reste));

      setState(() {
        clients = data;
        isLoading = false;
      });
    } catch (e) {
      print("Erreur dettes: $e");

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erreur de chargement des dettes")),
      );
    }
  }

  Color getColor(String statut) {
    switch (statut) {
      case "PAYE":
        return Colors.green;
      case "PARTIEL":
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String getScore(DetteClient c) {
    if (c.statut == "PAYE") return "A+";
    if (c.statut == "PARTIEL") return "B";
    return "C";
  }

  Color getScoreColor(String score) {
    switch (score) {
      case "A+":
        return Colors.green;
      case "B":
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  List<DetteClient> getFiltered() {
    List<DetteClient> list = clients;

    if (selectedFilter != "ALL") {
      list = list.where((c) => c.statut == selectedFilter).toList();
    }

    if (searchQuery.isNotEmpty) {
      list = list.where((c) {
        final nom = c.nom.toLowerCase();
        final tel = (c.telephone ?? "").toLowerCase();
        final query = searchQuery.toLowerCase();

        return nom.contains(query) || tel.contains(query);
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = getFiltered();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('customer_debts')),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadData,
              child: Column(
                children: [
                  // 🔍 SEARCH
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: context.tr('search_name_phone'),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchQuery = value;
                        });
                      },
                    ),
                  ),

                  // 🔥 FILTRES
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ["ALL", "PAYE", "PARTIEL", "IMPAYE"]
                            .map((f) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: ChoiceChip(
                                    label: Text(f),
                                    selected: selectedFilter == f,
                                    onSelected: (_) {
                                      setState(() => selectedFilter = f);
                                    },
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 🔥 LISTE / VIDE
                  if (list.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          "Aucune dette trouvée",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final c = list[index];
                          final score = getScore(c);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            elevation: 3,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: getColor(c.statut),
                                child: const Icon(Icons.person,
                                    color: Colors.white),
                              ),

                              // ✅ NOM SEUL
                              title: Text(
                                c.nom,
                                overflow: TextOverflow.ellipsis,
                              ),

                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  if (c.telephone != null)
                                    Text("Tel: ${c.telephone}"),

                                  Text(
                                      "Facturé: ${c.totalFacture.toStringAsFixed(0)}"),
                                  Text(
                                      "Payé: ${c.totalPaye.toStringAsFixed(0)}"),
                                  Text(
                                      "Reste: ${c.reste.toStringAsFixed(0)}"),
                                ],
                              ),

                              // ✅ SCORE + STATUT ALIGNÉS
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: getScoreColor(score),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      score,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  Text(
                                    c.statut,
                                    style: TextStyle(
                                      color: getColor(c.statut),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),

                              onTap: () {
                                // 🔥 futur
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
