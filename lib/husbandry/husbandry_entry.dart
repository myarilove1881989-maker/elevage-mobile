import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/v2_components.dart';
import 'husbandry_common.dart';
import 'technical_screen.dart';
import 'reproduction_screen.dart';

class HusbandryEntry extends StatefulWidget {
  const HusbandryEntry({
    super.key,
    required this.api,
    this.reproduction = false,
    this.initialSpeciesId,
    this.initialLotId,
  });
  final ApiService api;
  final bool reproduction;
  final int? initialSpeciesId, initialLotId;
  @override
  State<HusbandryEntry> createState() => _HusbandryEntryState();
}

class _HusbandryEntryState extends State<HusbandryEntry> {
  List<Map<String, dynamic>> species = [], lots = [];
  int? selectedSpecies, selectedLot;
  bool loading = true, opened = false;
  String? error;
  int generation = 0;
  String get title =>
      widget.reproduction ? 'Suivi de reproduction' : 'Technique';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final ticket = ++generation, identity = ApiService.sessionIdentity;
    try {
      final caps = await HusbandryService(widget.api).get('capabilities/');
      final all = await widget.api.getActiveLots();
      if (!mounted ||
          ticket != generation ||
          identity != ApiService.sessionIdentity) {
        return;
      }
      if (caps['read'] != true) throw StateError('OWNER_REQUIRED');
      species = (caps['species'] as List)
          .map((x) => Map<String, dynamic>.from(x as Map))
          .where((x) => !widget.reproduction || x['reproduction'] == true)
          .toList();
      lots = all
          .map((x) => Map<String, dynamic>.from(x as Map))
          .where((x) => species.any((s) => s['id'] == x['espece']))
          .toList();
      selectedLot = lots.any((l) => l['id'] == widget.initialLotId)
          ? widget.initialLotId
          : null;
      selectedSpecies = selectedLot == null
          ? (species.any((s) => s['id'] == widget.initialSpeciesId)
                ? widget.initialSpeciesId
                : null)
          : lots.firstWhere((l) => l['id'] == selectedLot)['espece'] as int;
      setState(() {
        loading = false;
        opened = selectedLot != null;
        error = null;
      });
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          loading = false;
          error = hError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (opened && selectedLot != null) {
      final lot = lots.firstWhere((x) => x['id'] == selectedLot);
      final sp = species.firstWhere((x) => x['id'] == lot['espece']);
      return widget.reproduction
          ? ReproductionScreen(api: widget.api, lot: lot, species: sp)
          : TechnicalScreen(api: widget.api, lot: lot, species: sp);
    }
    return V2Scaffold(
      appBar: V2AppBar(title: Text(title)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: HSection(
                title: title,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HError(error),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: selectedSpecies,
                      decoration: const V2InputDecoration(labelText: 'Espèce'),
                      items: species
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: s['id'] as int,
                              child: Text(
                                '${s['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        selectedSpecies = v;
                        selectedLot = null;
                      }),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<int>(
                      key: ValueKey(selectedSpecies),
                      isExpanded: true,
                      initialValue: selectedLot,
                      decoration: const V2InputDecoration(labelText: 'Lot'),
                      items: lots
                          .where((l) => l['espece'] == selectedSpecies)
                          .map(
                            (l) => DropdownMenuItem<int>(
                              value: l['id'] as int,
                              child: Text(
                                '${l['nom']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => selectedLot = v),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: selectedLot == null
                          ? null
                          : () => setState(() => opened = true),
                      child: const Text('Ouvrir'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
