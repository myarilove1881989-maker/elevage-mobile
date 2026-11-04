import 'package:flutter/material.dart';

/// Shared presentation for every dashboard KPI; no business calculation here.
class DashboardKpiCard extends StatelessWidget {
  const DashboardKpiCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.content,
    this.onTap,
  });
  final String title;
  final IconData icon;
  final Color color;
  final Widget content;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4E8EC)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 34, color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height:
                        56 * (MediaQuery.textScalerOf(context).scale(14) / 14),
                    child: Center(child: content),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum ConsumableLevel { neutral, good, low, critical }

/// A configured whole-product threshold never applies to a filtered subset.
ConsumableLevel consumableLevel(
  List details, {
  required bool feed,
  bool filtered = false,
  bool uncertain = false,
}) {
  if (filtered || uncertain) return ConsumableLevel.neutral;
  var unknown = false, low = false, configured = false;
  for (final p in details) {
    if (p['archived'] == true) continue;
    final threshold = num.tryParse('${p['alert_threshold']}');
    if (threshold == null || threshold <= 0) {
      unknown = true;
      continue;
    }
    final quantity = num.tryParse('${p[feed ? 'confirmed' : 'usable']}');
    if (quantity == null) {
      unknown = true;
      continue;
    }
    configured = true;
    if (quantity <= 0) return ConsumableLevel.critical;
    if (quantity <= threshold) low = true;
  }
  if (low) return ConsumableLevel.low;
  if (unknown || !configured) return ConsumableLevel.neutral;
  return ConsumableLevel.good;
}

String consumableQuantity(Object? value) {
  final text = '${value ?? 0}';
  if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(text)) return text;
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

Color levelColor(ConsumableLevel level) => switch (level) {
  ConsumableLevel.good => Colors.green,
  ConsumableLevel.low => Colors.orange,
  ConsumableLevel.critical => Colors.red,
  ConsumableLevel.neutral => Colors.blueGrey,
};
String levelLabel(ConsumableLevel level) => switch (level) {
  ConsumableLevel.good => 'Stock satisfaisant',
  ConsumableLevel.low => 'Stock faible',
  ConsumableLevel.critical => 'Stock critique ou épuisé',
  ConsumableLevel.neutral => 'Niveau à vérifier',
};
