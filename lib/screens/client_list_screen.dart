import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import 'client_detail_screen.dart';

class ClientListScreen extends StatefulWidget {
  final ApiService apiService;

  const ClientListScreen({super.key, required this.apiService});

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  List clients = [];
  bool loading = true;

  String search = ""; // 🔍 recherche

  @override
  void initState() {
    super.initState();
    loadClients();
  }

  Future<void> loadClients() async {
    try {
      final res = await widget.apiService.getClients();

      if (!mounted) return;

      setState(() {
        clients = res;
        loading = false;
      });
    } catch (e) {
      print("❌ ERREUR CLIENTS: $e");

      if (!mounted) return;

      setState(() => loading = false);
    }
  }

  // ================= CREATE CLIENT =================
  void addClient() {
    final nomController = TextEditingController();
    final telController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('new_customer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomController,
              decoration: InputDecoration(hintText: context.tr('name')),
            ),
            TextField(
              controller: telController,
              decoration: InputDecoration(hintText: context.tr('phone')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final nom = nomController.text.trim();
              final tel = telController.text.trim();

              if (nom.isEmpty || tel.isEmpty) return;

              await widget.apiService.createClient(nom, tel);

              Navigator.pop(context);
              loadClients();
            },
            child: Text(context.tr('add')),
          )
        ],
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    // 🔍 FILTRAGE
    final filteredClients = clients.where((c) {
      final nom = (c["nom"] ?? "").toString().toLowerCase();
      final tel = (c["telephone"] ?? "").toString().toLowerCase();

      return nom.contains(search) || tel.contains(search);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('customers'))),

      floatingActionButton: FloatingActionButton(
        onPressed: addClient,
        child: const Icon(Icons.add),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [

                // 🔍 BARRE DE RECHERCHE
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                decoration: InputDecoration(
                      hintText: context.tr('search_customer'),
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        search = value.toLowerCase();
                      });
                    },
                  ),
                ),

                // 📋 LISTE
                Expanded(
                  child: filteredClients.isEmpty
                      ? Center(child: Text(context.tr('no_customer')))
                      : ListView.builder(
                          itemCount: filteredClients.length,
                          itemBuilder: (_, i) {
                            final c =
                                filteredClients[i] as Map<String, dynamic>;

                            return Card(
                              margin: const EdgeInsets.all(8),
                              child: ListTile(
                                title: Text(c["nom"] ?? ""),
                                subtitle: Text(c["telephone"] ?? ""),
                                trailing:
                                    const Icon(Icons.arrow_forward_ios),

                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ClientDetailScreen(
                                        clientId: c["id"],
                                        nom: c["nom"] ?? "",
                                        telephone:
                                            c["telephone"] ?? "",
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
