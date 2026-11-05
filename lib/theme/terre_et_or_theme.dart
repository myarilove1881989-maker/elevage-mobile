import '../widgets/v2_components.dart';
import 'design_system_v2.dart';
import 'package:flutter/material.dart';

abstract final class TerreEtOrColors {
  static const navy = Color(0xFF064B6E);
  static const teal = Color(0xFF167B77);
  static const green = Color(0xFF279B68);
  static const gold = Color(0xFFE4A13A);
  static const cream = Color(0xFFFCF7FF);
  static const paleGold = Color(0xFFFFF1D8);
  static const ink = Color(0xFF17384D);
  static const muted = Color(0xFF6C7E78);
  static const border = Color(0xFF315D79);
}

ThemeData terreEtOrTheme(BuildContext context) => designSystemV2(Theme.of(context));

class TerreEtOrHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const TerreEtOrHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: V2Colors.green.withValues(alpha:0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: V2Colors.green, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: TerreEtOrColors.ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: TerreEtOrColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TerreEtOrPanel extends StatelessWidget {
  final Widget child;

  const TerreEtOrPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color:V2Colors.border,width:1.25),
        boxShadow: [
          BoxShadow(
            color: TerreEtOrColors.navy.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class TerreEtOrDateTile extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const TerreEtOrDateTile({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return V2PickerTile(label:'Date',value:label.replaceFirst(RegExp(r'^Date\s*:\s*'),''),icon:Icons.calendar_month_outlined,onTap:onTap);
  }
}
