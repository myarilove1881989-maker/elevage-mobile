import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Preserve existing namespaces, aliases and cipher choices. A key error must
// surface to the caller instead of deleting secrets needed by pending originals.
const protectedSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(resetOnError: false),
);
