import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final settings = AppSettings.instance;
  late final TextEditingController cityController;
  late String language;
  late String currency;
  late String countryCode;

  @override
  void initState() {
    super.initState();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('settings_saved'))),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: countryCode,
            decoration: InputDecoration(
              labelText: '${context.tr('country')} (${context.tr('optional')})',
              border: const OutlineInputBorder(),
            ),
            items: [
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
