import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'forgot_password_screen.dart';

/// The token stays in the URL fragment and request body, never in API paths.
class ResetPasswordLinkScreen extends StatefulWidget {
  const ResetPasswordLinkScreen({super.key, required this.api, required this.token});
  final ApiService api;
  final String token;
  @override
  State<ResetPasswordLinkScreen> createState() => _ResetPasswordLinkScreenState();
}

class _ResetPasswordLinkScreenState extends State<ResetPasswordLinkScreen> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool checking = true, busy = false, valid = false, completed = false;
  String error = '';
  @override
  void initState() { super.initState(); validate(); }
  Future<void> validate() async {
    try {
      await widget.api.validatePasswordResetLink(widget.token);
      if (mounted) setState(() { valid = true; checking = false; });
    } catch (_) {
      if (mounted) setState(() { checking = false; error = 'Lien invalide, expiré ou déjà utilisé. Demandez un nouveau lien.'; });
    }
  }
  Future<void> submit() async {
    if (busy || !valid) return;
    if (password.text.length < 8) {
      setState(() { error = 'Utilisez au moins 8 caractères. Le serveur vérifie les règles de votre compte.'; }); return;
    }
    if (password.text != confirmation.text) {
      setState(() { error = 'Les mots de passe ne correspondent pas.'; }); return;
    }
    setState(() { busy = true; error = ''; });
    try {
      await widget.api.confirmPasswordResetLink(widget.token, password.text);
      await widget.api.logout();
      password.clear(); confirmation.clear();
      if (mounted) setState(() { completed = true; valid = false; });
    } catch (failure) {
      if (mounted) setState(() { error = failure.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { busy = false; });
    }
  }
  @override
  void dispose() { password.dispose(); confirmation.dispose(); super.dispose(); }
  void login() => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(
    settings: const RouteSettings(name: '/'),
    builder: (_) => LoginScreen(apiService: widget.api)), (_) => false);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nouveau mot de passe')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 450),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (checking) const Center(child: CircularProgressIndicator()),
          if (completed) ...[
            const Text('Mot de passe modifié. Connectez-vous avec votre nouveau mot de passe.'),
            ElevatedButton(onPressed: login, child: const Text('Se connecter')),
          ] else if (valid) ...[
            const Text('Choisissez un nouveau mot de passe. Ce lien est temporaire et utilisable une seule fois.'),
            const SizedBox(height: 16),
            TextField(controller: password, obscureText: true, enableSuggestions: false,
              autocorrect: false, autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Nouveau mot de passe', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: confirmation, obscureText: true, enableSuggestions: false,
              autocorrect: false, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: busy ? null : submit,
              child: Text(busy ? 'Enregistrement…' : 'Enregistrer le nouveau mot de passe')),
          ],
          if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16),
            child: Text(error, style: const TextStyle(color: Colors.red))),
          if (!checking && !completed) TextButton(onPressed: busy ? null : () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ForgotPasswordScreen(apiService: widget.api))),
            child: const Text('Demander un nouveau lien')),
        ]),
      ),
    )),
  );
}
