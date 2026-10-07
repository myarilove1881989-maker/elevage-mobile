import 'farm_cache.dart';

class OfflineDatabaseUnavailable {
  static const available = false;
}

Future<FarmCache> openAndroidFarmDatabase({required int farmId,required Uri server}) =>
    Future.error(UnsupportedError('Le mode tablette est disponible sur Android.'));
Future<void> closeAndroidFarmDatabase({required int farmId,required Uri server}) async {}
