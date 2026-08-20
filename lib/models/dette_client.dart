class DetteClient {
  final int id;
  final String nom;
  final String? telephone; // 🔥 AJOUT
  final double totalFacture;
  final double totalPaye;
  final double reste;
  final String statut;

  DetteClient({
    required this.id,
    required this.nom,
    this.telephone,
    required this.totalFacture,
    required this.totalPaye,
    required this.reste,
    required this.statut,
  });

  factory DetteClient.fromJson(Map<String, dynamic> json) {
    return DetteClient(
      id: json["id"],
      nom: json["nom"],
      telephone: json['telephone'], // 🔥 AJOUT
      totalFacture: (json["total_facture"] ?? 0).toDouble(),
      totalPaye: (json["total_paye"] ?? 0).toDouble(),
      reste: (json["reste"] ?? 0).toDouble(),
      statut: json["statut"] ?? "IMPAYE",
    );
  }
}