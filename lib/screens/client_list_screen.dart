import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
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

  String countryName(dynamic code) {
    final normalized = (code ?? '').toString();
    for (final country in AppSettings.countries) {
      if (country.code == normalized) {
        return country.label(AppSettings.instance.languageCode);
      }
    }
    return normalized;
  }

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
  Future<void> addClient() async {
    final nomController = TextEditingController();
    final telController = TextEditingController();
    final villeController = TextEditingController();
    var pays = AppSettings.instance.countryCode;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('new_customer')),
          content: SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: pays.isEmpty ? null : pays,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: '${context.tr('country')} (${context.tr('optional')})',
                  ),
                  items: AppSettings.sortedCountries(
                    AppSettings.instance.languageCode,
                  )
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.code,
                          child: Text(
                            item.label(AppSettings.instance.languageCode),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => pays = value ?? ''),
                ),
                TextField(
                  controller: villeController,
                  decoration: InputDecoration(
                    hintText: '${context.tr('city')} (${context.tr('optional')})',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('cancel')),
            ),
            TextButton(
              onPressed: () async {
                final nom = nomController.text.trim();
                final tel = telController.text.trim();
                if (nom.isEmpty || tel.isEmpty) return;

                await widget.apiService.createClient(
                  nom,
                  tel,
                  pays: pays,
                  ville: villeController.text.trim(),
                );

                if (!context.mounted) return;
                Navigator.pop(context);
                loadClients();
              },
              child: Text(context.tr('add')),
            ),
          ],
        ),
      ),
    );
    nomController.dispose();
    telController.dispose();
    villeController.dispose();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    // 🔍 FILTRAGE
    final filteredClients = clients.where((c) {
      final nom = (c["nom"] ?? "").toString().toLowerCase();
      final tel = (c["telephone"] ?? "").toString().toLowerCase();
      final ville = (c["ville"] ?? "").toString().toLowerCase();
      final pays = (c["pays"] ?? "").toString().toLowerCase();

      return nom.contains(search) ||
          tel.contains(search) ||
          ville.contains(search) ||
          pays.contains(search);
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
                                subtitle: Text(
                                  [
                                    c["telephone"],
                                    c["ville"],
                                    countryName(c["pays"]),
                                  ]
                                      .where(
                                        (value) =>
                                            value != null &&
                                            value.toString().trim().isNotEmpty,
                                      )
                                      .join(' • '),
                                ),
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
