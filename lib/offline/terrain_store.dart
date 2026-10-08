abstract interface class TerrainStore {
  Future<List<Map<String,dynamic>>> projectedPage(String collection,{int offset=0,int limit=50,int? taskUserId,String search=''});
}
