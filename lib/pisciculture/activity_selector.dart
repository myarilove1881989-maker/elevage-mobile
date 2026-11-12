import 'package:flutter/material.dart';
import '../theme/design_system_v2.dart';

class ActivitySelector extends StatelessWidget {
  const ActivitySelector({
    super.key,
    required this.aquatic,
    required this.onSelect,
  });
  final bool aquatic;
  final ValueChanged<bool> onSelect;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Row(
      children: [
        for (final value in [false, true])
          Expanded(
            child: Semantics(
              selected: value == aquatic,
              child: TextButton(
                key: ValueKey('activity-${value ? 'aquatic' : 'terrestrial'}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  shape: const RoundedRectangleBorder(),
                  backgroundColor: value == aquatic
                      ? const Color(0xFFE8F2F8)
                      : Colors.white,
                  foregroundColor: V2Colors.navy,
                  side: BorderSide(
                    color: value == aquatic
                        ? V2Colors.green
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                onPressed: () => onSelect(value),
                child: Text(value ? 'Pisciculture' : 'Élevage'),
              ),
            ),
          ),
      ],
    ),
  );
}
