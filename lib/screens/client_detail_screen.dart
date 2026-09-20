import 'package:flutter/material.dart';
import '../services/app_settings.dart';
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
  double totalFacture = 0;
  double totalPaye = 0;

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

      final ventesData = v ?? [];

      double facture = 0;
      double paye = 0;

      for (final vente in ventesData) {
        facture += (vente["montant_total"] ?? 0).toDouble();
        paye += (vente["montant_paye"] ?? 0).toDouble();
      }

      setState(() {
        balance = (b["balance"] ?? 0).toDouble();
        ventes = ventesData;
        payments = p ?? [];

        totalFacture = facture;
        totalPaye = paye;

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

  Color getStatusColor(String status) {
    switch (status) {
      case "PAYE":
        return Colors.green;
      case "PARTIEL":
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String formatStatus(String status) {
    switch (status) {
      case "PAYE":
        return "PAYÉ";
      case "PARTIEL":
        return "PARTIEL";
      case "IMPAYE":
        return "IMPAYÉ";
      default:
        return status;
    }
  }

  String formatMoney(dynamic value) {
    final number = (value ?? 0).toDouble();

    return AppSettings.instance.formatMoney(number, decimals: 2);
  }

  // ================= PAIEMENT =================

  Future<void> payer(int venteId, double resteVente) async {
  final controller = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setStateDialog) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.payment),
              SizedBox(width: 10),
              Text("Enregistrer un paiement"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Text(
                      "Reste à payer sur cette vente",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(resteVente),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: resteVente > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: "Montant",
                  hintText: "Ex : 50000",
                  prefixIcon: Icon(Icons.euro),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: resteVente <= 0
                      ? null
                      : () {
                          controller.text =
                              resteVente.toStringAsFixed(2);
                        },
                  icon: const Icon(Icons.flash_on),
                  label: const Text("Payer le reste"),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isPaying
                  ? null
                  : () {
                      Navigator.pop(context);
                    },
              child: const Text("Annuler"),
            ),

            ElevatedButton(
              onPressed: isPaying
                  ? null
                  : () async {
                      final montant =
                          double.tryParse(controller.text.trim());

                      if (montant == null || montant <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Veuillez saisir un montant valide",
                            ),
                          ),
                        );
                        return;
                      }

                      if (montant > resteVente) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Montant supérieur au reste de cette vente",
                            ),
                          ),
                        );
                        return;
                      }

                      setState(() {
                        isPaying = true;
                      });

                      setStateDialog(() {});

                      try {
                        await api.createPayment(
                          widget.clientId,
                          venteId,
                          montant,
                        );

                        if (!mounted) return;

                        Navigator.pop(context);

                        await load();

                        if (!mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Paiement enregistré"),
                          ),
                        );
                      } catch (e) {
                        print("ERREUR PAIEMENT: $e");

                        if (!mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Erreur : $e"),
                          ),
                        );
                      }

                      if (mounted) {
                        setState(() {
                          isPaying = false;
                        });
                      }
                    },
              child: isPaying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text("Valider"),
            ),
          ],
        );
      },
    ),
  );

  controller.dispose();
}

  // ================= CONTACT =================

  Future<void> appeler() async {
    if (widget.telephone.trim().isEmpty) return;

    final uri = Uri.parse("tel:${widget.telephone}");

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> sms() async {
    if (widget.telephone.trim().isEmpty) return;

    final uri = Uri.parse("sms:${widget.telephone}");

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ================= HEADER CLIENT =================

  Widget buildClientHeader() {
    final bool hasDebt = balance > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor:
                hasDebt ? Colors.orange.shade100 : Colors.green.shade100,
            child: Icon(
              Icons.person,
              size: 32,
              color: hasDebt ? Colors.orange.shade800 : Colors.green.shade700,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            widget.nom,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),

          if (widget.telephone.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.telephone,
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
          ],

          const SizedBox(height: 16),

          Text(
            "Reste à payer",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            formatMoney(balance),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: hasDebt ? Colors.red : Colors.green,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: appeler,
                icon: const Icon(Icons.phone, size: 18),
                label: const Text("Appeler"),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: sms,
                icon: const Icon(Icons.sms, size: 18),
                label: const Text("SMS"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= RESUME FINANCIER =================

  Widget buildFinancialSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: buildSummaryCard(
              title: "FACTURÉ",
              value: totalFacture,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: buildSummaryCard(
              title: "PAYÉ",
              value: totalPaye,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: buildSummaryCard(
              title: "RESTE",
              value: balance,
              color: balance > 0 ? Colors.red : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSummaryCard({
    required String title,
    required double value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFE4E8EC),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            formatMoney(value),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ================= SECTION TITLE =================

  Widget buildSectionTitle(
    String title, {
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Colors.blueGrey.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ================= VENTE =================

  Widget buildVenteCard(dynamic v) {
    final status = v["statut"] ?? "IMPAYE";

    final montantTotal = (v["montant_total"] ?? 0).toDouble();
    final montantPaye = (v["montant_paye"] ?? 0).toDouble();
    final reste = (v["reste"] ?? 0).toDouble();
    final venteId = v["id"];

    final statusColor = getStatusColor(status);

    final espece = v["espece"] ?? "";
    final lot = v["lot_nom"] ?? "";
    final quantite = v["quantite"] ?? 0;
    final date = v["date"] ?? "";
    

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.blueGrey.shade700,
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        espece.toString().isNotEmpty
                            ? espece.toString()
                            : "Espèce inconnue",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Lot : ${lot.toString().isNotEmpty ? lot : "Non renseigné"}",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    formatStatus(status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: buildVenteInfo(
                      "Quantité",
                      "$quantite",
                    ),
                  ),
                  Expanded(
                    child: buildVenteInfo(
                      "Facturé",
                      formatMoney(montantTotal),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: buildAmountLine(
                    "Payé",
                    montantPaye,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: buildAmountLine(
                    "Reste",
                    reste,
                    reste > 0 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 5),
                Text(
                  date.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            if (reste > 0) ...[
  const SizedBox(height: 12),

  SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: () => payer(
        (venteId as num).toInt(),
        reste,
      ),
      icon: const Icon(Icons.payment, size: 18),
      label: const Text("Payer"),
    ),
  ),
],
          ],
        ),
      ),
    );
  }

  Widget buildVenteInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget buildAmountLine(
    String label,
    double value,
    Color color,
  ) {
    return Row(
      children: [
        Text(
          "$label : ",
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
        Flexible(
          child: Text(
            formatMoney(value),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // ================= PAIEMENT =================

  Widget buildPaymentCard(dynamic p) {
    final montant = (p["montant"] ?? 0).toDouble();
    final date = p["date"] ?? "";
    final note = p["note"];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      elevation: 1,
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                color: Colors.green.shade700,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatMoney(montant),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    date.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  if (note != null &&
                      note.toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nom),
        elevation: 0,
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  buildClientHeader(),

                  buildFinancialSummary(),

                  // ================= VENTES =================

                  buildSectionTitle(
                    "Ventes",
                    icon: Icons.shopping_cart_outlined,
                  ),

                  if (ventes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 42,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Aucune vente",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  ...ventes.map(
                    (v) => buildVenteCard(v),
                  ),

                  // ================= PAIEMENTS =================

                  buildSectionTitle(
                    "Paiements",
                    icon: Icons.payments_outlined,
                  ),

                  if (payments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                      child: Column(
                        children: [
                          Icon(
                            Icons.payments_outlined,
                            size: 42,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Aucun paiement enregistré",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  ...payments.map(
                    (p) => buildPaymentCard(p),
                  ),

                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }
}
