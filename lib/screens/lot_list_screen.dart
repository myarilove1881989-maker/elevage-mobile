import '../widgets/owner_maintenance_actions.dart';
import '../widgets/mutation_refresh.dart';
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

class _LotListScreenState extends State<LotListScreen> with MutationRefresh<LotListScreen> {
  late final Future<bool> _ownerMaintenance = ownerMaintenanceAllowed(widget.apiService);
  @override
  Future<void> refreshAfterMutation() async { await fetchLots(); }
  List<dynamic> lots = [];
  bool isLoading = true;
  bool hasLoaded = false;
  bool showClosed=false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    fetchLots();
  }

  Future<void> fetchLots() async {
    markDataFresh();
    if (mounted) {
      setState(() { isLoading = true; loadError = null; });
    }
    try {
      final result = await widget.apiService.getLots();

      if (!mounted) return;

      setState(() {
        lots = result;
        hasLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadError = hasLoaded
            ? 'Actualisation impossible. Les lots affichés sont conservés.'
            : 'Lots indisponibles. Réessayez lorsque la connexion le permet.';
      });
    } finally {
      if (mounted) { setState(() => isLoading = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && !hasLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final visibleLots=lots.where((lot)=>ApiService.isLotClosed(lot as Map)==showClosed).toList();
    return Theme(
      data: terreEtOrTheme(context),
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('batches'))),
        body: Column(
          children: [
            if (isLoading) const LinearProgressIndicator(),
            Wrap(spacing:8,children:[ChoiceChip(label:const Text('Lots actifs'),selected:!showClosed,onSelected:(_)=>setState(()=>showClosed=false)),
              ChoiceChip(label:const Text('Lots clôturés'),selected:showClosed,onSelected:(_)=>setState(()=>showClosed=true))]),
            OwnerMaintenanceActions(api:widget.apiService,kind:'lots',label:'un lot',access:_ownerMaintenance,
              remove:false,onChanged:fetchLots),
            if (loadError != null) Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(loadError!, textAlign: TextAlign.center),
                TextButton(onPressed: isLoading ? null : fetchLots,
                  child: const Text('Réessayer')),
              ])),
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
                  itemCount: visibleLots.isEmpty ? 1 : visibleLots.length,
                  itemBuilder: (context, index) {
                    if (visibleLots.isEmpty) {
                      return Padding(padding: const EdgeInsets.all(24),
                        child: Text(hasLoaded ? (showClosed?'Aucun lot clôturé.':'Aucun lot actif.')
                            : 'Les données ne sont pas disponibles.',
                          textAlign: TextAlign.center));
                    }
                    final lot = visibleLots[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: TerreEtOrColors.paleGold,
                          foregroundColor: TerreEtOrColors.gold,
                          child: Icon(
                            lot['type_production'] == 'OEUFS'
                                ? Icons.egg_outlined
                                : Icons.inventory_2_outlined,
                          ),
                        ),
                        title: Text(lot["nom"]),
                        subtitle: Text(
                          lot['type_production'] == 'OEUFS'
                              ? "Ponte · ${context.tr('stock')}: ${lot['stock']} poules"
                              : "${context.tr('stock')}: ${lot['stock']}",
                        ),
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

                            // Stay on the refreshed list; the dashboard refreshes on return.
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
