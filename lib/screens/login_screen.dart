import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'farmer_access_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/initial_password.dart';
import 'initial_password_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/register_screen.dart';
import 'package:app_elevage/screens/forgot_password_screen.dart';
import 'package:app_elevage/l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  final ApiService apiService;
  final bool sessionExpired;
  final bool restoreFailed;

  const LoginScreen({
    super.key,
    required this.apiService,
    this.sessionExpired = false,
    this.restoreFailed = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool _obscurePassword = true;
  String errorMessage = '';

  Future<void> handleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final success = await widget.apiService.login(
        usernameController.text.trim(),
        passwordController.text,
      );

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      if (success) {
        final caps=await widget.apiService.get('/me/capabilities/');
        if(!mounted) return;
        if (kIsWeb && caps['role'] != 'OWNER') {
          await widget.apiService.logout();
          passwordController.clear();
          if (!mounted) return;
          setState(() { errorMessage = 'L’espace opérateur nécessite l’application Android et son appareil autorisé.'; });
          return;
        }
        if(caps['role']=='OPERATEUR' && !kIsWeb && defaultTargetPlatform==TargetPlatform.android) {
          final runtime=createFarmerRuntime();
          try {
            final api=await runtime.signIn(usernameController.text.trim(),passwordController.text);
            passwordController.clear();
            if(!mounted) {runtime.dispose();return;}
            Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>FarmerSessionHost(runtime:runtime,api:api)));
          } catch (_) {runtime.dispose();rethrow;}
          return;
        }
        ApiService.farmerSession=false;
        final prefs=await SharedPreferences.getInstance();await prefs.setString('session_kind','owner');
        if(!mounted) return;
        passwordController.clear();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                DashboardScreen(apiService: widget.apiService),
          ),
        );
      } else {
        setState(() {
          errorMessage = context.tr('invalid_credentials');
        });
      }
    } on InitialPasswordRequired catch(requiredChange) {
      passwordController.clear();
      if (!mounted) {return;}
      final changed=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>
        InitialPasswordScreen(api:widget.apiService,changeToken:requiredChange.changeToken)));
      if(mounted) {setState(() {isLoading=false;errorMessage=changed==true?
        'Mot de passe modifié. Connectez-vous avec votre nouveau mot de passe.':
        'Le changement de mot de passe est nécessaire pour vous connecter.';});}
    } on ApiConnectionException {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = context.tr('server_unreachable');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = context.tr('invalid_credentials');
      });
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusMessage = errorMessage.isNotEmpty
        ? errorMessage
        : widget.sessionExpired
        ? context.tr('session_expired')
        : widget.restoreFailed
        ? context.tr('session_restore_failed')
        : '';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if(!kIsWeb && defaultTargetPlatform==TargetPlatform.android)
                    Padding(padding:const EdgeInsets.only(bottom:24),child:SizedBox(width:double.infinity,
                      child:FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:const Color(0xFF0A9B4A),
                        padding:const EdgeInsets.symmetric(vertical:18,horizontal:20)),
                        icon:const Icon(Icons.agriculture_outlined,size:32),
                        label:const Column(children:[Text('Espace éleveur',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
                          Text('Accéder à mon compte')]),
                        onPressed:isLoading?null:()=>Navigator.push(context,
                          MaterialPageRoute(builder:(_)=>const FarmerAccessScreen()))))),
                  Image.asset('assets/images/elevage_logo.png', height: 180),
                  if(!kIsWeb && defaultTargetPlatform==TargetPlatform.android)
                    const Text('Connexion propriétaire',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
                  const SizedBox(height: 40),
                  TextField(
                    controller: usernameController,
                    decoration: InputDecoration(
                      labelText: context.tr('username'),
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: context.tr('password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? context.tr('show_password')
                            : context.tr('hide_password'),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ForgotPasswordScreen(
                                    apiService: widget.apiService,
                                  ),
                                ),
                              );
                            },
                      child: Text(context.tr('forgot_password')),
                    ),
                  ),
                  if (statusMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A9B4A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              context.tr('login'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
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
                    child: Text(
                      context.tr('create_account'),
                      style: const TextStyle(
                        color: Color(0xFF063B63),
                        fontWeight: FontWeight.bold,
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
