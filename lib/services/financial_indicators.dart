/// Operating balance excluding animal purchases, tax, depreciation and stock valuation.
/// This is not accounting profit or gross margin.
double? operatingBalanceRate(Map kpis) {
  double? number(dynamic v)=>v is num?v.toDouble():double.tryParse('$v');
  final revenue=number(kpis['chiffre_affaires']),expenses=number(kpis['depenses']);
  if(revenue==null || expenses==null || !revenue.isFinite || !expenses.isFinite || revenue<=0) return null;
  return (revenue-expenses)/revenue*100;
}
