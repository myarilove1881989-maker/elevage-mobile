class Lot {
  final int id;
  final String nom;
  final String? especeNom;
  final int stock;

  Lot({
    required this.id,
    required this.nom,
    this.especeNom,
    required this.stock,
  });

  factory Lot.fromJson(Map<String, dynamic> json) {
    return Lot(
      id: json['id'],
      nom: json['nom'],
      especeNom: json['espece_nom'],
      stock: json['stock'] ?? 0,
    );
  }
}