import 'package:flutter/material.dart';

/// Web spacing only; deliberately has no draft, preference or storage effects.
class DashboardField extends StatelessWidget {
  const DashboardField({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child);
}
