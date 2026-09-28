class Lot {
  final int id;
  final String nom;
  final String? especeNom;
  final int stock;
  final String typeProduction;
  final String statutProduction;

  Lot({
    required this.id,
    required this.nom,
    this.especeNom,
    required this.stock,
    this.typeProduction = 'CHAIR',
    this.statutProduction = 'ELEVAGE',
  });

  factory Lot.fromJson(Map<String, dynamic> json) {
    return Lot(
      id: json['id'],
      nom: json['nom'],
      especeNom: json['espece_nom'],
      stock: json['stock'] ?? 0,
      typeProduction: json['type_production']?.toString() ?? 'CHAIR',
      statutProduction: json['statut_production']?.toString() ?? 'ELEVAGE',
    );
  }
}
