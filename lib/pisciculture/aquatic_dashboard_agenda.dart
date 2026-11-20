import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../widgets/detail_widgets.dart';
import '../theme/terre_et_or_theme.dart';
import '../services/api_service.dart';
import 'aquatic_service.dart';

class AquaticDashboardAgenda extends StatefulWidget {
  const AquaticDashboardAgenda({
    super.key,
    required this.service,
    required this.filters,
    required this.openAgenda,
    required this.addTask,
    required this.canPlan,
  });
  final AquaticService service;
  final Map<String, String> filters;
  final VoidCallback openAgenda, addTask;
  final bool canPlan;
  @override
  State<AquaticDashboardAgenda> createState() => _AquaticDashboardAgendaState();
}

class _AquaticDashboardAgendaState extends State<AquaticDashboardAgenda> {
  DateTime focused = DateTime.now(), selected = DateTime.now();
  List<Map<String, dynamic>> tasks = [];
  bool loading = true;
  String? error;
  int epoch = 0;
  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    epoch++;
    super.dispose();
  }

  Future<void> load() async {
    final n = ++epoch, identity = ApiService.sessionIdentity;
    setState(() {
      loading = true;
      tasks = [];
      error = null;
    });
    try {
      final rows = await widget.service.list(
        'agenda/?${Uri(queryParameters: {...widget.filters, 'from': day(DateTime(focused.year, focused.month, 1).subtract(const Duration(days: 7))), 'to': day(DateTime(focused.year, focused.month + 1, 1).add(const Duration(days: 7)))}).query}',
      );
      if (mounted && n == epoch && identity == ApiService.sessionIdentity)
        setState(() {
          tasks = rows;
          loading = false;
        });
    } catch (_) {
      if (mounted && n == epoch && identity == ApiService.sessionIdentity)
        setState(() {
          loading = false;
          error = 'Agenda indisponible.';
        });
    }
  }

  List<Map<String, dynamic>> at(DateTime d) =>
      tasks.where((t) => t['date'] == day(d)).toList();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final calendar = DetailSection(
        title: 'Calendrier des tâches',
        child: Column(
          children: [
            if (loading) const LinearProgressIndicator(),
            if (error != null) TextButton(onPressed: load, child: Text(error!)),
            TableCalendar<Map<String, dynamic>>(
              firstDay: DateTime(2000),
              lastDay: DateTime(2100),
              focusedDay: focused,
              locale: 'fr_FR',
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              availableGestures: AvailableGestures.horizontalSwipe,
              selectedDayPredicate: (d) => isSameDay(d, selected),
              eventLoader: at,
              onDaySelected: (s, f) => setState(() {
                selected = s;
                focused = f;
              }),
              onPageChanged: (f) {
                focused = f;
                load();
              },
              calendarStyle: const CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: TerreEtOrColors.green,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: TerreEtOrColors.teal,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      );
      final list = DetailSection(
        title: 'Tâches du jour',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(day(selected)),
            const SizedBox(height: 12),
            if (!loading && error == null && at(selected).isEmpty)
              const Text('Aucune tâche.'),
            for (final task in at(selected))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${task['title']}'),
                subtitle: Text(
                  '${task['status'] == 'DONE'
                      ? 'Terminée'
                      : task['status'] == 'CANCELLED'
                      ? 'Annulée'
                      : 'À faire'}',
                ),
                onTap: widget.openAgenda,
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: widget.openAgenda,
                  child: const Text('Agenda'),
                ),
                if (widget.canPlan)
                  FilledButton.icon(
                    onPressed: widget.addTask,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter'),
                  ),
              ],
            ),
          ],
        ),
      );
      return c.maxWidth >= 1000
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: calendar),
                const SizedBox(width: 18),
                Expanded(child: list),
              ],
            )
          : Column(children: [calendar, const SizedBox(height: 18), list]);
    },
  );
}
