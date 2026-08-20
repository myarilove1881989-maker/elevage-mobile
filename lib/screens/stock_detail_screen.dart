import 'package:flutter/material.dart';
import '../services/api_service.dart';

class StockDetailScreen extends StatefulWidget {
  final ApiService apiService;
  final int lotId;

  const StockDetailScreen({
    super.key,
    required this.apiService,
    required this.lotId,
  });

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {

  Map data = {};
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final res = await widget.apiService.getStockDetail(widget.lotId);

      if (!mounted) return;

      setState(() {
        data = res;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Widget buildCard(String title, dynamic value, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 6,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18, // 🔥 icône plus grande
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 10),

        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 20, // 🔥 GROS chiffre
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
          ),
        ),
      ],
    ),
  );
}
  @override
  Widget build(BuildContext context) {

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 🔥 ERREUR
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Erreur")),
        body: Center(child: Text(error!)),
      );
    }

    final stockInitial = data["stock_initial"] ?? 0;
    final restant = data["stock_restant"] ?? 0;
    final vendu = data["vendu"] ?? 0;
    final perdu = data["perdu"] ?? 0;

    final mortalite = data["mortalite"] ?? 0;
    final vol = data["vol"] ?? 0;
    final don = data["don"] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Analyse Stock"),
      ),

      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
          children: [

            // ================= KPI =================
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.2,
              children: [
                buildCard("Stock initial", stockInitial, Colors.blue, Icons.inventory),
                buildCard("Restant", restant, Colors.green, Icons.check_circle),
                buildCard("Vendu", vendu, Colors.orange, Icons.shopping_cart),
                buildCard("Perdu", perdu, Colors.red, Icons.warning),
              ],
            ),

            const SizedBox(height: 16),

            // ================= DETAIL =================
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Détail des pertes",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close, color: Colors.red, size: 24),
                    ),
                    title: const Text(
                      "Mortalité",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    trailing: Text(
                      mortalite.toString(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.lock, color: Colors.orange, size: 24),
                    ),
                    title: const Text(
                      "Vol",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    trailing: Text(
                      vol.toString(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.card_giftcard, color: Colors.blue, size: 24),
                    ),
                    title: const Text(
                      "Don",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    trailing: Text(
                      don.toString(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  // ================= KPI FINAL =================
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insights, color: Colors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Taux de perte : ${stockInitial > 0 ? ((perdu / stockInitial) * 100).toStringAsFixed(1) : 0} %",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}