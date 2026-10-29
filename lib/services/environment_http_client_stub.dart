import 'package:http/http.dart' as http;
import '../config.dart';
http.Client environmentHttpClient(EnvironmentConfig config) {
  if (config.isLab) throw StateError('Laboratoire natif uniquement.');
  return http.Client();
}
