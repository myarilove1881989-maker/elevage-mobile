abstract interface class ScreenSnapshotStore {
  Future<void> saveScreenSnapshot({required int userId,required int credentialVersion,
    required String path,required Object payload});
  Future<Object?> screenSnapshot({required int userId,required int credentialVersion,required String path});
}
