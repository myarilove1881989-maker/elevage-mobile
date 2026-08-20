import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ClientDetailScreen extends StatefulWidget {
  final int clientId;
  final String nom;
  final String telephone;

  const ClientDetailScreen({
    super.key,
    required this.clientId,
    required this.nom,
    required this.telephone,
  });

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  final api = ApiService();

  double balance = 0;
  List ventes = [];
  List payments = [];
  bool loading = true;

  bool isPaying = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final b = await api.getClientBalance(widget.clientId);
      final v = await api.getClientVentes(widget.clientId);
      final p = await api.get("/clients/${widget.clientId}/payments/");

      if (!mounted) return;

      setState(() {
        balance = (b["balance"] ?? 0).toDouble();
        ventes = v ?? [];
        payments = p ?? [];
        loading = false;
      });
    } catch (e) {
      print("ERREUR LOAD CLIENT: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
        ventes = [];
        payments = [];
      });
    }
  }

  Color getColor(String status) {
    switch (status) {
      case "PAYE":
        return Colors.green;
      case "PARTIEL":
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  // ================= PAIEMENT =================
  Future<void> payer() async {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text("Paiement"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Dette actuelle: ${balance.toStringAsFixed(2)} €",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: "Montant"),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    controller.text = balance.toStringAsFixed(0);
                  },
                  icon: const Icon(Icons.flash_on),
                  label: const Text("Payer le reste"),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isPaying
                    ? null
                    : () async {
                        final montant =
                            double.tryParse(controller.text);

                        if (montant == null || montant <= 0) return;

                        if (montant > balance) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text("Montant supérieur à la dette"),
                            ),
                          );
                          return;
                        }

                        setState(() => isPaying = true);
                        setStateDialog(() {});

                        try {
                          await api.createPayment(
                              widget.clientId, montant);

                          Navigator.pop(context);
                          await load();

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text("Paiement enregistré")),
                          );
                        } catch (e) {
                          print("ERREUR PAIEMENT: $e");

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Erreur: $e")),
                          );
                        }

                        setState(() => isPaying = false);
                      },
                child: isPaying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2),
                      )
                    : const Text("Valider"),
              )
            ],
          );
        },
      ),
    );
  }

  void appeler() async {
    final uri = Uri.parse("tel:${widget.telephone}");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void sms() async {
    final uri = Uri.parse("sms:${widget.telephone}");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.nom)),

      floatingActionButton: FloatingActionButton(
        onPressed: payer,
        child: const Icon(Icons.payment),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [

                // HEADER
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blueGrey.shade50,
                  child: Column(
                    children: [
                      Text(
                        "Solde: ${balance.toStringAsFixed(2)} €",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: balance > 0
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.phone),
                            onPressed: appeler,
                          ),
                          IconButton(
                            icon: const Icon(Icons.sms),
                            onPressed: sms,
                          ),
                        ],
                      )
                    ],
                  ),
                ),

                // LISTE
                Expanded(
                  child: ListView(
                    children: [

                      // VENTES
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          "Ventes",
                          style: TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ),

                      ...ventes.map((v) {
                        final status = v["statut"] ?? "IMPAYE";

                        return Card(
                          margin: const EdgeInsets.all(8),
                          child: ListTile(
                            title: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [

                                // 🔥 LOT + ESPECE
                                Text(
                                  "${v["espece"] ?? ""} - ${v["lot_nom"] ?? ""}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                Text("${v["montant_total"]} €"),

                                Text(
                                  "Payé : ${v["montant_paye"]} €",
                                ),

                                Text(
                                  "Reste : ${v["reste"]} €",
                                  style: TextStyle(
                                    color: (v["reste"] ?? 0) > 0
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                ),

                                Text(v["date"] ?? ""),
                              ],
                            ),
                            trailing: Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5),
                              decoration: BoxDecoration(
                                color: getColor(status),
                                borderRadius:
                                    BorderRadius.circular(20),
                              ),
                              child: Text(
                                status,
                                style: const TextStyle(
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        );
                      }),

                      // PAIEMENTS
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          "Paiements",
                          style: TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ),

                      if (payments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text("Aucun paiement"),
                        ),

                      ...payments.map((p) {
                        return Card(
                          margin: const EdgeInsets.all(8),
                          color: Colors.green.shade50,
                          child: ListTile(
                            leading: const Icon(Icons.payment,
                                color: Colors.green),
                            title: Text("${p["montant"]} €"),
                            subtitle:
                                Text(p["date"] ?? ""),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}