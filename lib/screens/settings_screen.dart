import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'offline_tablet_screen.dart';
import 'supervision_screen.dart';
import 'user_management_screen.dart';
import '../services/api_service.dart';

import '../l10n/app_localizations.dart';
import '../services/app_settings.dart';
import '../services/access_error.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key,this.apiService});
  final ApiService? apiService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool owner=false;
  bool checkingOwner=false;
  String? ownerError;
  String? ownerSession;
  Future<void> loadOwner() async {
    if(checkingOwner) return;
    setState(() {checkingOwner=true;owner=false;ownerSession=null;ownerError=null;});
    final api=widget.apiService??ApiService();
    final session=ApiService.sessionIdentity;
    if(session==null) {if(mounted) setState(() {checkingOwner=false;ownerError='Connectez-vous pour vérifier votre accès à la création des utilisateurs.';});if(widget.apiService==null) api.close();return;}
    try {
      final data=await api.get('/me/capabilities/');
      if(mounted && session==(ApiService.sessionIdentity)) {
        if(data is! Map || !{'OWNER','OPERATEUR'}.contains(data['role'])) throw const FormatException();
        setState(() {owner=data['role']=='OWNER';ownerSession=session;});
      }
    } catch (error) {if(mounted && session==(ApiService.sessionIdentity)) setState(() {ownerError=safeAccessError(error, 'Vérification du rôle');});}
    finally {if(mounted) setState(() {checkingOwner=false;});if(widget.apiService==null) api.close();}
  }
  final settings = AppSettings.instance;
  late final TextEditingController cityController;
  late String language;
  late String currency;
  late String countryCode;

  @override
  void initState() {
    super.initState();
    loadOwner();
    language = settings.languageCode;
    currency = settings.currencyCode;
    countryCode = settings.countryCode;
    cityController = TextEditingController(text: settings.city);
  }

  @override
  void dispose() {
    cityController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    await settings.save(
      language: language,
      currency: currency,
      selectedCountryCode: countryCode,
      selectedCity: cityController.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr('settings_saved'))));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if(checkingOwner) const LinearProgressIndicator(),
          if(ownerError!=null) ListTile(title:Text(ownerError!),trailing:TextButton(onPressed:checkingOwner?null:loadOwner,child:const Text('Réessayer'))),
          if(owner && ownerSession==(ApiService.sessionIdentity)) ListTile(
            leading:const Icon(Icons.manage_accounts),title:const Text('Création des utilisateurs'),
            onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const UserManagementScreen()))),
          if(owner && ownerSession==(ApiService.sessionIdentity)) ListTile(leading:const Icon(Icons.fact_check),title:const Text('Supervision et journal d’activité'),
            onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SupervisionScreen()))),
          if(!kIsWeb && defaultTargetPlatform==TargetPlatform.android && owner && ownerSession==ApiService.sessionIdentity)
            ListTile(leading:const Icon(Icons.tablet_android),title:const Text('Configurer ma tablette'),
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const OfflineTabletScreen(configure:true)))),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: countryCode,
            decoration: InputDecoration(
              labelText: '${context.tr('country')} (${context.tr('optional')})',
              border: const OutlineInputBorder(),
            ),
            items:
                [
                      const CountryOption('', '—', '—', 'XAF'),
                      ...AppSettings.sortedCountries(language),
                    ]
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.code,
                        child: Text(item.label(language)),
                      ),
                    )
                    .toList(),
            onChanged: (value) {
              setState(() {
                countryCode = value ?? '';
                if (countryCode.isNotEmpty) {
                  currency = AppSettings.countries
                      .firstWhere((item) => item.code == countryCode)
                      .currencyCode;
                }
              });
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: cityController,
            decoration: InputDecoration(
              labelText: '${context.tr('city')} (${context.tr('optional')})',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: language,
            decoration: InputDecoration(
              labelText: context.tr('language'),
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 'fr', child: Text(context.tr('french'))),
              DropdownMenuItem(value: 'en', child: Text(context.tr('english'))),
            ],
            onChanged: (value) => setState(() => language = value ?? 'fr'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: currency,
            decoration: InputDecoration(
              labelText: context.tr('currency'),
              border: const OutlineInputBorder(),
            ),
            items: AppSettings.currencies
                .map(
                  (item) => DropdownMenuItem(
                    value: item.code,
                    child: Text('${item.label(language)} (${item.symbol})'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => currency = value ?? 'XAF'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save_outlined),
            label: Text(context.tr('save')),
          ),
        ],
      ),
    );
  }
}
