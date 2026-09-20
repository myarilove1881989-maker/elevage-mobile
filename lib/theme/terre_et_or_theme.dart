import 'package:flutter/material.dart';

abstract final class TerreEtOrColors {
  static const navy = Color(0xFF064B6E);
  static const teal = Color(0xFF167B77);
  static const green = Color(0xFF279B68);
  static const gold = Color(0xFFE4A13A);
  static const cream = Color(0xFFFFFBF4);
  static const paleGold = Color(0xFFFFF1D8);
  static const ink = Color(0xFF17384D);
  static const muted = Color(0xFF6C7E78);
  static const border = Color(0xFFE5DED0);
}

ThemeData terreEtOrTheme(BuildContext context) {
  final base = Theme.of(context);
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: TerreEtOrColors.border),
  );

  return base.copyWith(
    scaffoldBackgroundColor: TerreEtOrColors.cream,
    colorScheme: base.colorScheme.copyWith(
      primary: TerreEtOrColors.green,
      secondary: TerreEtOrColors.gold,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: TerreEtOrColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(
          color: TerreEtOrColors.green,
          width: 2,
        ),
      ),
      prefixIconColor: TerreEtOrColors.gold,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shadowColor: TerreEtOrColors.navy.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: TerreEtOrColors.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: TerreEtOrColors.green.withValues(alpha: 0.45),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: TerreEtOrColors.green,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: TerreEtOrColors.green,
    ),
  );
}

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
              color: TerreEtOrColors.paleGold,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: TerreEtOrColors.gold, size: 28),
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
        borderRadius: BorderRadius.circular(20),
        border: const Border(
          top: BorderSide(color: TerreEtOrColors.gold, width: 5),
        ),
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
  final VoidCallback onTap;

  const TerreEtOrDateTile({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TerreEtOrColors.paleGold.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: const Icon(Icons.calendar_month, color: TerreEtOrColors.gold),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right, color: TerreEtOrColors.navy),
        onTap: onTap,
      ),
    );
  }
}
