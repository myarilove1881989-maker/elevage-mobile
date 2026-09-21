import 'package:flutter/material.dart';

import '../theme/terre_et_or_theme.dart';

class DetailMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? caption;
  final IconData icon;
  final Color color;

  const DetailMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: [
          BoxShadow(
            color: TerreEtOrColors.navy.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: TerreEtOrColors.muted, fontSize: 12)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: TerreEtOrColors.ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 3),
                  Text(caption!, style: const TextStyle(color: TerreEtOrColors.muted, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DetailSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const DetailSection({super.key, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: TerreEtOrColors.navy.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: TerreEtOrColors.ink, fontSize: 17, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: const TextStyle(color: TerreEtOrColors.muted, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

