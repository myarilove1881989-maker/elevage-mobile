import 'offline_grant.dart';

abstract interface class FarmCache {
  Future<void> replaceConfirmedCache(String collection,List<Map<String,dynamic>> rows);
  Future<List<Map<String,dynamic>>> cachedPage(String collection,{int offset=0,int limit=50,int? taskUserId});
  Future<void> beginCacheRefresh(String collection);
  Future<void> stageConfirmedPage(String collection,List<Map<String,dynamic>> rows);
  Future<void> commitCacheRefresh(String collection,{int? taskUserId,int? businessRevision});
  Future<void> saveOperatorProfile(VerifiedOfflineGrant grant,String displayName);
  Future<List<Map<String,dynamic>>> operatorProfiles();
}
