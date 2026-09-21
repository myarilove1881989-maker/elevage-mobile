import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:app_elevage/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/models/dette_client.dart';

String? globalToken;

class ApiService {

  // ✅ URL API centralisée (compatible local + Render)
  static String get baseUrl {
    final configuredUrl = Config.apiUrl.trim();
    return configuredUrl.endsWith('/')
        ? configuredUrl.substring(0, configuredUrl.length - 1)
        : configuredUrl;
  }

  static String? token;

  // ================= HEADERS =================
  Map<String, String> _headers() {
    final currentToken = token ?? globalToken;
    print("TOKEN UTILISÉ: $currentToken");

    if (currentToken == null) {
      print("⚠️ Token manquant");
      return {
        "Content-Type": "application/json",
      };
    }

    return {
      "Authorization": "Bearer $currentToken",
      "Content-Type": "application/json",
    };
  }

  // ================= HELPER RESPONSE =================
Future<dynamic> _handleResponse(
  http.Response response, {
  bool clearSessionOnUnauthorized = true,
}) async {
  print("📥 STATUS: ${response.statusCode}");
  print("📥 RESPONSE: ${response.body}");

  // ✅ SUCCÈS
  if (response.statusCode >= 200 && response.statusCode < 300) {
    if (response.body.isEmpty) return true;
    return jsonDecode(response.body);
  }

  // 🔒 TOKEN EXPIRÉ
  if (response.statusCode == 401 && clearSessionOnUnauthorized) {
    token = null;
    globalToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("token");

    throw Exception("Session expirée, reconnectez-vous 🔒");
  }

  // Message retourné par le backend, lorsqu'il est disponible.
  try {
    final data = jsonDecode(response.body);

    if (data is Map) {
      if (data.containsKey("message")) {
        return Future.error(Exception(data["message"]));
      }

      if (data.containsKey("error")) {
        return Future.error(Exception(data["error"]));
      }

      if (data.containsKey("errors")) {
        return Future.error(Exception(data["errors"].toString()));
      }

      // Les validations Django utilisent directement le nom du champ
      // (username, email, password...). On restitue leur message précis.
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) {
          return Future.error(Exception(value.join(' ')));
        }
        if (value is String && value.trim().isNotEmpty) {
          return Future.error(Exception(value));
        }
      }
    }

    return Future.error(Exception(data.toString()));
  } on FormatException {
    // Réponse non JSON : message générique mais compréhensible.
    throw Exception("Erreur API (${response.statusCode})");
  }
}
// ================= REGISTER =================
Future<dynamic> register(String username, String email, String password) async {
  final response = await http.post(
    Uri.parse("$baseUrl/register/"),
    headers: {
      "Content-Type": "application/json",
    },
    body: jsonEncode({
      "username": username,
      "email": email,
      "password": password,
    }),
  );

  print("REGISTER RESPONSE: ${response.body}");

  return await _handleResponse(response);
}
  // ================= PASSWORD RESET =================
Future<void> requestPasswordReset(String email) async {
  final response = await http.post(
    Uri.parse("$baseUrl/password-reset/request/"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({"email": email}),
  );
  await _handleResponse(response, clearSessionOnUnauthorized: false);
}

Future<String> verifyPasswordReset(String email, String code) async {
  final response = await http.post(
    Uri.parse("$baseUrl/password-reset/verify/"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({"email": email, "code": code}),
  );
  final data = await _handleResponse(
    response,
    clearSessionOnUnauthorized: false,
  );
  return data["reset_token"] as String;
}

Future<void> confirmPasswordReset(
  String email,
  String resetToken,
  String newPassword,
) async {
  final response = await http.post(
    Uri.parse("$baseUrl/password-reset/confirm/"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "email": email,
      "reset_token": resetToken,
      "new_password": newPassword,
    }),
  );
  await _handleResponse(response, clearSessionOnUnauthorized: false);
}

  // ================= LOGIN =================
Future<bool> login(String username, String password) async {
  final response = await http.post(
    Uri.parse("$baseUrl/token/"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "username": username,
      "password": password,
    }),
  );

  print("LOGIN RESPONSE: ${response.body}");

  final data = await _handleResponse(
    response,
    clearSessionOnUnauthorized: false,
  );

  // 🔥 Nettoyage ancien token
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove("token");

  // ✅ Nouveau token
  token = data["access"];
  globalToken = token;

  await prefs.setString("token", token!);
  await prefs.setString("username", username);

  return true;
}

  // ================= LOAD TOKEN =================
Future<void> loadToken() async {
  final prefs = await SharedPreferences.getInstance();
  final savedToken = prefs.getString("token");

  if (savedToken != null && savedToken.isNotEmpty) {
    token = savedToken;
    globalToken = savedToken;
    print("TOKEN CHARGÉ: $savedToken");
  } else {
    print("Aucun token trouvé");
  }
}

  // ================= DASHBOARD =================
  Future<Map<String, dynamic>> getDashboard({int? especeId}) async {
  try {
    print("🌐 AVANT REQUETE");

    final uri = Uri.parse("$baseUrl/dashboard/").replace(
      queryParameters: especeId == null
          ? null
          : {"espece": especeId.toString()},
    );

    final response = await http
        .get(
          uri,
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 30));

    print("✅ APRES REQUETE");

    return await _handleResponse(response);

  } catch (e) {
    print("❌ ERREUR HTTP: $e");
    rethrow;
  }
}

  // ================= LOTS =================
  Future<List<dynamic>> getLots() async {
    final response = await http.get(
      Uri.parse("$baseUrl/lots/"),
      headers: _headers(),
    );
    return await _handleResponse(response);
  }

  Future<Map<String, dynamic>> getLotDetail(int lotId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/lots/$lotId/"),
      headers: _headers(),
    );
    return await _handleResponse(response);
  }
  
  // ================= ESPECES =================
  Future<List<dynamic>> getEspeces() async {
    final response = await http.get(
      Uri.parse("$baseUrl/especes/"),
      headers: _headers(),
    );
    return await _handleResponse(response);
  }

  Future<dynamic> createEspece(String nom) async {
    final response = await http.post(
      Uri.parse("$baseUrl/especes/"),
      headers: _headers(),
      body: jsonEncode({"nom": nom}),
    );
    return await _handleResponse(response);
  }

  // ================= DELETE DEPENSE =================
Future<bool> deleteDepense(int id) async {
  final response = await http.delete(
    Uri.parse("$baseUrl/depenses/delete/$id/"),
    headers: _headers(),
  );

  await _handleResponse(response);
  return true;
}

// ================= STOCK DETAIL =================
Future<Map<String, dynamic>> getStockDetail(int lotId) async {
  final response = await http.get(
    Uri.parse("$baseUrl/stock-detail/?lot=$lotId"),
    headers: _headers(),
  );

  return await _handleResponse(response);
}

  // ================= DEPENSE =================
  Future<List<dynamic>> getCategoriesDepense() async {
    final response = await http.get(
      Uri.parse("$baseUrl/categories-depense/"),
      headers: _headers(),
    );
    return await _handleResponse(response);
  }

  Future<bool> createDepense({
    required int lotId,
    required int categorieId,
    required double montant,
    required DateTime date,
    String? note,
  }) async {
    final body = {
      "lot": lotId,
      "categorie": categorieId,
      "montant": montant,
      "date": date.toIso8601String().split("T")[0],
      if (note != null && note.isNotEmpty) "note": note,
    };

    final response = await http.post(
      Uri.parse("$baseUrl/depenses/create/"),
      headers: _headers(),
      body: jsonEncode(body),
    );

    await _handleResponse(response);
    return true;
  }

  // ================= TOTAL DETTES =================
Future<double> getTotalDettes() async {
  final response = await http.get(
    Uri.parse("$baseUrl/clients/total-dettes/"),
    headers: _headers(),
  );

  final res = await _handleResponse(response);

  return (res["total_dettes"] ?? 0).toDouble();
}

 // ================= DETTES CLIENTS =================

Future<List<DetteClient>> getDettesClients() async {
  final res = await get("/dettes-clients"); // ⚠️ slash important

  return (res as List)
      .map((e) => DetteClient.fromJson(e))
      .toList();
  }
  // ================= ACHAT =================
 Future<bool> createAchat({
  required String nomLot,
  required int especeId,
  required int quantite,
  required double prixTotal,
  required double prixUnitaire,
  required DateTime date,
}) async {
  final body = {
    "nom_lot": nomLot,
    "espece": especeId,
    "quantite": quantite,
    "prix_total": prixTotal,
    "prix_unitaire": prixUnitaire,
    "date": date.toIso8601String().split("T")[0],
  };

  final response = await http.post(
    Uri.parse("$baseUrl/achats/create/"),
    headers: _headers(),
    body: jsonEncode(body),
  );

  await _handleResponse(response);
  return true;
}

  // ================= MOUVEMENT =================
  Future<bool> createMouvement({
  required int lotId,
  required String type,
  required int quantite,
  required double prixUnitaire,
  required DateTime date,
  int? clientId,
}) async {

  // 🔥 validation métier
  if (type == "VENTE" && clientId == null) {
    return false;
  }

  final body = {
    "lot": lotId,
    "type_mouvement": type,
    "quantite": quantite,
    "prix_unitaire": prixUnitaire,
    "date": date.toIso8601String().split("T")[0],
  };

  if (clientId != null) {
    body["client"] = clientId;
  }

  final response = await http.post(
    Uri.parse("$baseUrl/mouvements/create/"),
    headers: _headers(),
    body: jsonEncode(body),
  );

  await _handleResponse(response);
  return true;
}
Future<List<dynamic>> getClients() async {
  final response = await http.get(
    Uri.parse("$baseUrl/clients/"),
    headers: _headers(),
  );

  return await _handleResponse(response);
}

Future<void> createClient(
  String nom,
  String telephone, {
  String pays = '',
  String ville = '',
}) async {
  final response = await http.post(
    Uri.parse("$baseUrl/clients/create/"),
    headers: _headers(),
    body: jsonEncode({
      "nom": nom,
      "telephone": telephone,
      "pays": pays,
      "ville": ville,
    }),
  );

  await _handleResponse(response);
}

Future<Map<String, dynamic>> getClientBalance(int clientId) async {
  final res = await get("/clients/$clientId/balance/");
  return res;
}

Future<List<dynamic>> getClientVentes(int clientId) async {
  final res = await get("/clients/$clientId/ventes/");
  return res;
}

Future<bool> createPayment(
  int clientId,
  int venteId,
  double montant,
) async {
  final res = await post("/payments/create/", {
    "client": clientId,
    "vente": venteId,
    "montant": montant,
  });

  return res != null;
}

  // ================= DELETE =================
  Future<bool> deleteAchat(int id) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/achats/delete/$id/"),
      headers: _headers(),
    );
    await _handleResponse(response);
    return true;
  }

  Future<bool> deleteMouvement(int id) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/mouvements/delete/$id/"),
      headers: _headers(),
    );
    await _handleResponse(response);
    return true;
  }

  // ================= GENERIC GET =================
Future<dynamic> get(String endpoint) async {
  final normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/+'), '');
  final response = await http.get(
    Uri.parse("$normalizedBase/$normalizedEndpoint"),
    headers: _headers(),
  );

  return await _handleResponse(response);
}

// ================= GENERIC POST =================
Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
  final normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/+'), '');
  final response = await http.post(
    Uri.parse("$normalizedBase/$normalizedEndpoint"),
    headers: _headers(),
    body: jsonEncode(data),
  );

  return await _handleResponse(response);
}

  Future<List<dynamic>> getCA(int especeId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/ca-par-lot/?espece=$especeId"),
      headers: _headers(),
    );
    return await _handleResponse(response);
  }

  Future<List<dynamic>> getDepenses(int lotId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/depenses-detail/?lot=$lotId"),
      headers: _headers(),
    );
    return await _handleResponse(response);
  }

  Future<List<dynamic>> getMarge(int especeId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/marge-par-lot/?espece=$especeId"),
      headers: _headers(),
    );
    return await _handleResponse(response);
  }

  Future<List<dynamic>> getPerformanceLots() async {
  final res = await get("/performance-lots/");
  return res;
}

  Future<Map<String, dynamic>> getSpeciesPerformance({int? speciesId}) async {
    final suffix = speciesId == null ? '' : '?espece=$speciesId';
    final res = await get('/performance-especes/$suffix');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<dynamic>> getTasks() async {
  final response = await http.get(
    Uri.parse("$baseUrl/tasks/"),
    headers: _headers(), // ✅ CORRECT
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Erreur chargement tasks");
  }
}

Future<void> createTask(String title, DateTime date) async {
  final response = await http.post(
    Uri.parse("$baseUrl/tasks/"),
    headers: {
      "Authorization": "Bearer $globalToken",
      "Content-Type": "application/json",
    },
    body: jsonEncode({
      "title": title,
      "date": date.toIso8601String().split("T")[0],
    }),
  );

  if (response.statusCode != 201) {
    throw Exception("Erreur création task");
  }
}

Future<void> deleteTask(int id) async {
  final response = await http.delete(
    Uri.parse("$baseUrl/tasks/$id/"), // ✅ BONNE URL
    headers: _headers(),
  );

  print("STATUS: ${response.statusCode}");
  print("BODY: ${response.body}");

  await _handleResponse(response);
}

}
