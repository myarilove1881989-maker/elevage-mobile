import 'package:flutter/material.dart';

Future<String?> confirmCancellation(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (_) => CancellationDialog(title: title),
    );

class CancellationDialog extends StatefulWidget {
  const CancellationDialog({super.key, required this.title});
  final String title;
  @override
  State<CancellationDialog> createState() => _CancellationDialogState();
}

class _CancellationDialogState extends State<CancellationDialog> {
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('L’original et son historique seront conservés.'),
            TextFormField(
              controller: reason,
              maxLength: 10000,
              decoration: const InputDecoration(labelText: 'Motif obligatoire'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Indiquez le motif.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Retour'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate())
            Navigator.pop(context, reason.text.trim());
        },
        child: const Text('Confirmer l’annulation'),
      ),
    ],
  );
}
