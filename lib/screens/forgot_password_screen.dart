import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:app_elevage/services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final ApiService apiService;

  const ForgotPasswordScreen({
    super.key,
    required this.apiService,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  int step = 0;
  bool isLoading = false;
  bool hidePassword = true;
  bool hideConfirmation = true;
  String errorMessage = '';
  String? resetToken;

  Future<void> requestCode() async {
    final email = emailController.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => errorMessage = "Saisissez une adresse e-mail valide.");
      return;
    }

    await runRequest(() async {
      await widget.apiService.requestPasswordReset(email);
      if (!mounted) return;
      setState(() => step = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Si cette adresse existe, un code a été envoyé."),
        ),
      );
    });
  }

  Future<void> verifyCode() async {
    final code = codeController.text.trim();
    if (code.length != 6) {
      setState(() => errorMessage = "Saisissez le code à 6 chiffres.");
      return;
    }

    await runRequest(() async {
      resetToken = await widget.apiService.verifyPasswordReset(
        emailController.text.trim().toLowerCase(),
        code,
      );
      if (!mounted) return;
      setState(() => step = 2);
    });
  }

  Future<void> changePassword() async {
    final password = passwordController.text;
    if (password.length < 8) {
      setState(() => errorMessage = "Le mot de passe doit contenir au moins 8 caractères.");
      return;
    }
    if (password != confirmPasswordController.text) {
      setState(() => errorMessage = "Les mots de passe ne correspondent pas.");
      return;
    }

    await runRequest(() async {
      await widget.apiService.confirmPasswordReset(
        emailController.text.trim().toLowerCase(),
        resetToken!,
        password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mot de passe modifié avec succès.")),
      );
      Navigator.pop(context);
    });
  }

  Future<void> runRequest(Future<void> Function() action) async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = error
            .toString()
            .replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('forgot_password'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    step == 0
                        ? Icons.email_outlined
                        : step == 1
                            ? Icons.pin_outlined
                            : Icons.lock_reset,
                    size: 64,
                    color: const Color(0xFF0A9B4A),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    step == 0
                        ? "Recevoir un code"
                        : step == 1
                            ? "Vérifier le code"
                            : "Nouveau mot de passe",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step == 0
                        ? "Indiquez l'adresse e-mail associée à votre compte."
                        : step == 1
                            ? "Le code à 6 chiffres est valable pendant 10 minutes."
                            : "Choisissez un nouveau mot de passe sécurisé.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (step == 0)
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                decoration: InputDecoration(
                        labelText: context.tr('email'),
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  if (step == 1) ...[
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                        labelText: context.tr('verification_code'),
                        counterText: "",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: isLoading ? null : requestCode,
                      child: Text(context.tr('resend_code')),
                    ),
                  ],
                  if (step == 2) ...[
                    TextField(
                      controller: passwordController,
                      obscureText: hidePassword,
                      decoration: InputDecoration(
                        labelText: context.tr('new_password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => hidePassword = !hidePassword,
                          ),
                          icon: Icon(
                            hidePassword ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: hideConfirmation,
                      decoration: InputDecoration(
                        labelText: context.tr('confirm_password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: hideConfirmation
                              ? "Afficher le mot de passe"
                              : "Masquer le mot de passe",
                          onPressed: () => setState(
                            () => hideConfirmation = !hideConfirmation,
                          ),
                          icon: Icon(
                            hideConfirmation
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : step == 0
                              ? requestCode
                              : step == 1
                                  ? verifyCode
                                  : changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A9B4A),
                        foregroundColor: Colors.white,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              step == 0
                                  ? "Envoyer le code"
                                  : step == 1
                                      ? "Vérifier"
                                      : "Modifier le mot de passe",
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
