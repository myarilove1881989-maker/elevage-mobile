import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CurrencyOption {
  final String code;
  final String label;
  final String symbol;

  const CurrencyOption(this.code, this.label, this.symbol);
}

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const currencies = <CurrencyOption>[
    CurrencyOption('XAF', 'FCFA', 'FCFA'),
    CurrencyOption('EUR', 'Euro', '€'),
    CurrencyOption('GHS', 'Cedi ghanéen', 'GH₵'),
    CurrencyOption('NGN', 'Naira nigérian', '₦'),
  ];

  String languageCode = 'fr';
  String currencyCode = 'XAF';
  String country = '';
  String city = '';

  CurrencyOption get currency => currencies.firstWhere(
        (item) => item.code == currencyCode,
        orElse: () => currencies.first,
      );

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    languageCode = prefs.getString('settings_language') ?? 'fr';
    currencyCode = prefs.getString('settings_currency') ?? 'XAF';
    country = prefs.getString('settings_country') ?? '';
    city = prefs.getString('settings_city') ?? '';
  }

  Future<void> save({
    required String language,
    required String currency,
    required String selectedCountry,
    required String selectedCity,
  }) async {
    languageCode = language;
    currencyCode = currency;
    country = selectedCountry.trim();
    city = selectedCity.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings_language', languageCode);
    await prefs.setString('settings_currency', currencyCode);
    await prefs.setString('settings_country', country);
    await prefs.setString('settings_city', city);
    notifyListeners();
  }

  String formatMoney(dynamic value, {int decimals = 0}) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    final locale = languageCode == 'en' ? 'en_US' : 'fr_FR';
    final formatted = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: decimals,
    ).format(number);
    return currencyCode == 'XAF'
        ? '$formatted ${currency.symbol}'
        : '${currency.symbol}$formatted';
  }
}
