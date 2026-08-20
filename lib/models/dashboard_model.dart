class DashboardModel {
  final double chiffreAffaires;
  final double depenses;
  final double achats;
  final double marge;
  final int stockTotal;
  final int pertes;

  DashboardModel({
    required this.chiffreAffaires,
    required this.depenses,
    required this.achats,
    required this.marge,
    required this.stockTotal,
    required this.pertes,
  });

  factory DashboardModel.fromJson(Map<String, dynamic> json) {
    return DashboardModel(
      chiffreAffaires: (json['chiffre_affaires'] ?? 0).toDouble(),
      depenses: (json['depenses'] ?? 0).toDouble(),
      achats: (json['achats'] ?? 0).toDouble(),
      marge: (json['marge'] ?? 0).toDouble(),
      stockTotal: json['stock_total'] ?? 0,
      pertes: json['pertes'] ?? 0,
    );
  }
}