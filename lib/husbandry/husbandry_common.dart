import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../offline/outbox.dart' show newOperationUuid;
import '../widgets/v2_components.dart';
import '../theme/design_system_v2.dart';

class HusbandryService {
  HusbandryService(this.api);
  final ApiService api;
  static const prefix = '/elevage/v1/';
  Map<String, dynamic> command(Map<String, dynamic> fields) => {
    'schema_version': 1,
    'operation_uuid': newOperationUuid(),
    ...fields,
  };
  Future<Map<String, dynamic>> get(String path) async =>
      Map<String, dynamic>.from(await api.get('$prefix$path') as Map);
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> body,
  ) async =>
      Map<String, dynamic>.from(await api.post('$prefix$path', body) as Map);
  Future<List<Map<String, dynamic>>> list(String path) async {
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final data = await get(
        '$path${path.contains('?') ? '&' : '?'}limit=100${cursor == null ? '' : '&cursor=$cursor'}',
      );
      rows.addAll(
        (data['results'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      cursor = data['next_cursor'] as String?;
      if (rows.length > 2000) throw StateError('Réduisez la période.');
    } while (cursor != null);
    return rows;
  }
}

String hDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String hDate(dynamic raw) {
  final d = DateTime.tryParse('$raw')?.toLocal();
  return d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String hDateTime(dynamic raw) {
  final d = DateTime.tryParse('$raw')?.toLocal();
  return d == null
      ? '—'
      : '${hDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String hError(Object e) {
  final message = e is ApiHttpException
      ? (e.message?.toString() ?? e.toString())
      : e.toString();
  if (e is ApiConnectionException) return 'Connexion indisponible. Réessayez.';
  if (message.contains('VERSION') || message.contains('CYCLE_CLOSED')) {
    return 'Les données ont changé. Actualisez avant de réessayer.';
  }
  if (message.contains('OPERATION_UUID_REUSED')) {
    return 'Cette opération a déjà été traitée. Actualisez son historique.';
  }
  if (message.contains('VALUES_REQUIRED')) {
    return 'Renseignez au moins une valeur.';
  }
  if (message.contains('INVALID_BOUNDS')) {
    return 'Le minimum doit être inférieur ou égal au maximum.';
  }
  if (message.contains('PARAMETER_HIDDEN')) {
    return 'Un paramètre est masqué à cette date.';
  }
  if (message.contains('INTEGER')) {
    return 'Utilisez des effectifs entiers valides.';
  }
  if (message.contains('DECIMAL') || message.contains('INVALID_NUMBER')) {
    return 'Vérifiez les nombres saisis (six décimales au maximum).';
  }
  if (message.contains('LOT_CLOSED')) return 'Ce lot est clôturé.';
  if (message.contains('NOT_FOUND') || message.contains('OWNER_REQUIRED')) {
    return 'Accès ou référence indisponible.';
  }
  if (message.contains('INVALID_EVENT_DATE')) {
    return 'La date doit appartenir à ce cycle.';
  }
  if (message.contains('Réduisez la période')) return 'Réduisez la période.';
  return 'Vérifiez les champs puis réessayez.';
}

class HField extends StatelessWidget {
  const HField(
    this.label,
    this.controller, {
    super.key,
    this.numeric = false,
    this.lines = 1,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final bool numeric;
  final int lines;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: V2Field(
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: lines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        decoration: V2InputDecoration(labelText: label),
      ),
    ),
  );
}

class HDateField extends StatelessWidget {
  const HDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.withTime = false,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool withTime;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Semantics(
      button: true,
      label: '$label ${withTime ? hDateTime(value) : hDate(value)}',
      child: InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(1900),
            lastDate: DateTime(2100),
          );
          if (d == null || !context.mounted) return;
          if (withTime) {
            final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
            );
            if (t != null && context.mounted) {
              onChanged(DateTime(d.year, d.month, d.day, t.hour, t.minute));
            }
          } else {
            onChanged(d);
          }
        },
        child: InputDecorator(
          decoration: V2InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(withTime ? hDateTime(value) : hDate(value)),
        ),
      ),
    ),
  );
}

class HError extends StatelessWidget {
  const HError(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
}

class HSection extends StatelessWidget {
  const HSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: const TextStyle(color: V2Colors.muted)),
            ],
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    ),
  );
}

class HDialog extends StatelessWidget {
  const HDialog({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.busy = false,
    this.error,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool busy;
  final String? error;
  @override
  Widget build(BuildContext context) => V2AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [HError(error), ...children],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: busy ? null : onSave,
        child: Text(busy ? 'Enregistrement…' : 'Enregistrer'),
      ),
    ],
  );
}
