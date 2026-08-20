import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'lot_detail_screen.dart';

class LotListScreen extends StatefulWidget {
  final ApiService apiService;

  const LotListScreen({super.key, required this.apiService});

  @override
  State<LotListScreen> createState() => _LotListScreenState();
}

class _LotListScreenState extends State<LotListScreen> {

  List<dynamic> lots = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchLots();
  }

  Future<void> fetchLots() async {
    try {
      final result = await widget.apiService.getLots();

      if (!mounted) return;

      setState(() {
        lots = result;
        isLoading = false;
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Lots")),

      body: RefreshIndicator(
        onRefresh: fetchLots,
        child: ListView.builder(
          itemCount: lots.length,
          itemBuilder: (context, index) {
            final lot = lots[index];

            return Card(
              margin: const EdgeInsets.all(10),
              child: ListTile(
                title: Text(lot["nom"]),
                subtitle: Text("Stock: ${lot["stock"]}"),

                // 🔥 CLICK = DETAIL
                onTap: () async {

                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LotDetailScreen(
                        apiService: widget.apiService,
                        lotId: lot["id"],
                      ),
                    ),
                  );

                  // 🔥🔥🔥 ICI LA MAGIE
                  if (result == true) {

                    // refresh liste locale
                    await fetchLots();

                    // 🔥 remonter jusqu'au dashboard
                    if (mounted) {
                      Navigator.pop(context, true);
                    }
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }
}