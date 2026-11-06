/// Ephemeral recovery note only: never persisted, transmitted or auto-submitted.
class ExpiredDraft {
  static String? _user,_note;
  static DateTime? _at;
  static void remember(String user,String note) {_user=user;_note=note;_at=DateTime.now();}
  static String? take(String user) {
    if(_user!=user || _at==null)return null;
    final note=DateTime.now().difference(_at!)<const Duration(minutes:30)?_note:null;
    _user=null;_note=null;_at=null;return note;
  }
}
