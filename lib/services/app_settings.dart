import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CurrencyOption {
  final String code;
  final String labelFr;
  final String labelEn;
  final String symbol;

  const CurrencyOption(this.code, this.labelFr, this.labelEn, this.symbol);

  String label(String languageCode) =>
      languageCode == 'en' ? labelEn : labelFr;
}

class CountryOption {
  final String code;
  final String labelFr;
  final String labelEn;
  final String currencyCode;

  const CountryOption(
    this.code,
    this.labelFr,
    this.labelEn,
    this.currencyCode,
  );

  String label(String languageCode) =>
      languageCode == 'en' ? labelEn : labelFr;
}

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const currencies = <CurrencyOption>[
    CurrencyOption('XAF', 'Franc CFA (CEMAC)', 'CFA franc (CEMAC)', 'FCFA'),
    CurrencyOption('XOF', 'Franc CFA (UEMOA)', 'CFA franc (WAEMU)', 'CFA'),
    CurrencyOption('EUR', 'Euro', 'Euro', '€'),
    CurrencyOption('GHS', 'Cedi ghanéen', 'Ghanaian cedi', 'GH₵'),
    CurrencyOption('NGN', 'Naira nigérian', 'Nigerian naira', '₦'),
    CurrencyOption('CVE', 'Escudo cap-verdien', 'Cape Verdean escudo', 'Esc'),
    CurrencyOption('GMD', 'Dalasi gambien', 'Gambian dalasi', 'D'),
    CurrencyOption('GNF', 'Franc guinéen', 'Guinean franc', 'FG'),
    CurrencyOption('LRD', 'Dollar libérien', 'Liberian dollar', r'L$'),
    CurrencyOption('MRU', 'Ouguiya mauritanienne', 'Mauritanian ouguiya', 'UM'),
    CurrencyOption('SLE', 'Leone sierra-léonais', 'Sierra Leonean leone', 'Le'),
    CurrencyOption('GBP', 'Livre sterling', 'Pound sterling', '£'),
  ];

  static const countries = <CountryOption>[
    CountryOption('BJ', 'Bénin', 'Benin', 'XOF'),
    CountryOption('BF', 'Burkina Faso', 'Burkina Faso', 'XOF'),
    CountryOption('CV', 'Cap-Vert', 'Cape Verde', 'CVE'),
    CountryOption('CI', "Côte d'Ivoire", 'Ivory Coast', 'XOF'),
    CountryOption('GM', 'Gambie', 'Gambia', 'GMD'),
    CountryOption('GH', 'Ghana', 'Ghana', 'GHS'),
    CountryOption('GN', 'Guinée', 'Guinea', 'GNF'),
    CountryOption('GW', 'Guinée-Bissau', 'Guinea-Bissau', 'XOF'),
    CountryOption('LR', 'Libéria', 'Liberia', 'LRD'),
    CountryOption('ML', 'Mali', 'Mali', 'XOF'),
    CountryOption('MR', 'Mauritanie', 'Mauritania', 'MRU'),
    CountryOption('NE', 'Niger', 'Niger', 'XOF'),
    CountryOption('NG', 'Nigeria', 'Nigeria', 'NGN'),
    CountryOption('SN', 'Sénégal', 'Senegal', 'XOF'),
    CountryOption('SL', 'Sierra Leone', 'Sierra Leone', 'SLE'),
    CountryOption('TG', 'Togo', 'Togo', 'XOF'),
    CountryOption('CM', 'Cameroun', 'Cameroon', 'XAF'),
    CountryOption('CG', 'Congo (Congo-Brazzaville)', 'Congo (Congo-Brazzaville)', 'XAF'),
    CountryOption('GA', 'Gabon', 'Gabon', 'XAF'),
    CountryOption('GQ', 'Guinée équatoriale', 'Equatorial Guinea', 'XAF'),
    CountryOption('CF', 'République centrafricaine', 'Central African Republic', 'XAF'),
    CountryOption('TD', 'Tchad', 'Chad', 'XAF'),
    CountryOption('FR', 'France', 'France', 'EUR'),
    CountryOption('BE', 'Belgique', 'Belgium', 'EUR'),
    CountryOption('GB', 'Angleterre', 'England', 'GBP'),
  ];

  static List<CountryOption> sortedCountries(String languageCode) {
    final result = List<CountryOption>.of(countries);
    result.sort(
      (a, b) => a
          .label(languageCode)
          .toLowerCase()
          .compareTo(b.label(languageCode).toLowerCase()),
    );
    return result;
  }

  String languageCode = 'fr';
  String currencyCode = 'XAF';
  String countryCode = '';
  String city = '';

  CurrencyOption get currency => currencies.firstWhere(
        (item) => item.code == currencyCode,
        orElse: () => currencies.first,
      );

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    languageCode = prefs.getString('settings_language') ?? 'fr';
    currencyCode = prefs.getString('settings_currency') ?? 'XAF';
    final savedCountry = prefs.getString('settings_country') ?? '';
    countryCode = '';
    for (final item in countries) {
      if (item.code == savedCountry ||
          item.labelFr.toLowerCase() == savedCountry.toLowerCase()) {
        countryCode = item.code;
        break;
      }
    }
    city = prefs.getString('settings_city') ?? '';
  }

  Future<void> save({
    required String language,
    required String currency,
    required String selectedCountryCode,
    required String selectedCity,
  }) async {
    languageCode = language;
    currencyCode = currency;
    countryCode = selectedCountryCode;
    city = selectedCity.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings_language', languageCode);
    await prefs.setString('settings_currency', currencyCode);
    await prefs.setString('settings_country', countryCode);
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
