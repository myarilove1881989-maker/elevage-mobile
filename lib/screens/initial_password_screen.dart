import 'package:flutter/material.dart';
import '../services/api_service.dart';

class InitialPasswordScreen extends StatefulWidget {
  const InitialPasswordScreen({
    super.key,
    this.api,
    this.onChange,
    required this.changeToken,
  }) : assert(api != null || onChange != null);
  final ApiService? api;
  final Future<void> Function(String,String)? onChange;
  final String changeToken;
  @override
  State<InitialPasswordScreen> createState() => _InitialPasswordScreenState();
}

class _InitialPasswordScreenState extends State<InitialPasswordScreen> {
  final password = TextEditingController(), confirm = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    password.clear();
    confirm.clear();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (password.text.trim().length < 4 || password.text != confirm.text) {
      setState(
        () => error =
            'Utilisez au moins 4 caractères et confirmez le même mot de passe.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await (widget.onChange ?? widget.api!.changeInitialPassword)(widget.changeToken, password.text);
      password.clear();
      confirm.clear();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Changement refusé ou serveur indisponible. Vérifiez le mot de passe ; reconnectez-vous si la demande a expiré.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choisir votre code personnel')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Choisissez le code personnel que vous utiliserez pour vous connecter.',
            ),
            TextField(
              controller: password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Nouveau code personnel (4 caractères minimum)',
              ),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Confirmer le code personnel',
              ),
            ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'En cours…' : 'Enregistrer mon code'),
            ),
          ],
        ),
      ),
    ),
  );
}
