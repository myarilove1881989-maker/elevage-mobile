import 'package:flutter/material.dart';

/// Five equal metrics; the fifth is centered below the first four in portrait.
class DashboardMetricGrid extends StatelessWidget {
  const DashboardMetricGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 1000
          ? 5
          : box.maxWidth >= 550
          ? 2
          : 1;
      final height =
          190.0 *
          (MediaQuery.textScalerOf(context).scale(24) / 24).clamp(1.0, 2.0);
      final width = (box.maxWidth - 16 * (columns - 1)) / columns;
      Widget grid(List<Widget> items) => GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: width / height,
        children: items,
      );
      if (columns == 2 && children.length == 5)
        return Column(
          children: [
            grid(children.take(4).toList()),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                key: const Key('centered-management-card'),
                width: width,
                height: height,
                child: children.last,
              ),
            ),
          ],
        );
      return grid(children);
    },
  );
}
