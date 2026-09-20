import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import 'lot_detail_screen.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';

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

    return Theme(
      data: terreEtOrTheme(context),
      child: Scaffold(
      appBar: AppBar(title: Text(context.tr('batches'))),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: TerreEtOrHeader(
              icon: Icons.inventory_2_outlined,
              title: context.tr('batches'),
              subtitle: AppSettings.instance.languageCode == 'en'
                  ? 'Track your batches and available stock'
                  : 'Suivez vos lots et leur stock disponible',
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: fetchLots,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: lots.length,
                itemBuilder: (context, index) {
            final lot = lots[index];

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: TerreEtOrColors.paleGold,
                  foregroundColor: TerreEtOrColors.gold,
                  child: Icon(Icons.inventory_2_outlined),
                ),
                title: Text(lot["nom"]),
                subtitle: Text("${context.tr('stock')}: ${lot["stock"]}"),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: TerreEtOrColors.navy,
                ),

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
          ),
        ],
      ),
      ),
    );
  }
}
