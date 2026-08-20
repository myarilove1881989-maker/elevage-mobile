import 'package:flutter/material.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/register_screen.dart';

class LoginScreen extends StatefulWidget {
  final ApiService apiService; // ✅ injection

  const LoginScreen({
    super.key,
    required this.apiService,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  String errorMessage = '';

  Future<void> handleLogin() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final success = await widget.apiService.login(
        usernameController.text.trim(),
        passwordController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardScreen(
              apiService: widget.apiService, // ✅ même instance
            ),
          ),
        );
      } else {
        setState(() {
          errorMessage = "Identifiants invalides";
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Erreur : ${e.toString()}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("LOGIN TEST 🚀")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
            const SizedBox(height: 20),
            if (errorMessage.isNotEmpty)
              Text(errorMessage, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: isLoading ? null : handleLogin,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Login"),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RegisterScreen(
                            apiService: widget.apiService,
                          ),
                        ),
                      );
                    },
              child: const Text("Créer un compte"),
            ),
          ],
        ),
      ),
    );
  }
}
