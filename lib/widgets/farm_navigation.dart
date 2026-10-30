import 'package:flutter/material.dart';
import '../services/farm_session.dart';

enum FarmDestination {
  dashboard,
  lots,
  purchases,
  sales,
  expenses,
  movements,
  history,
  agenda,
  production,
  settings,
  users,
}

const farmDestinationLabels = {
  FarmDestination.dashboard: 'Tableau de bord',
  FarmDestination.lots: 'Lots',
  FarmDestination.purchases: 'Achats',
  FarmDestination.sales: 'Ventes',
  FarmDestination.expenses: 'Dépenses',
  FarmDestination.movements: 'Mouvements',
  FarmDestination.history: 'Historique',
  FarmDestination.agenda: 'Agenda',
  FarmDestination.production: 'Production',
  FarmDestination.settings: 'Paramètres',
  FarmDestination.users: 'Gestion des utilisateurs',
};

/// A shared menu with real destinations supplied by each current host.
class FarmNavigation extends StatelessWidget {
  const FarmNavigation({
    super.key,
    required this.actions,
    this.session,
    this.labels = const {},
  });
  final Map<FarmDestination, VoidCallback> actions;
  final FarmSession? session;
  final Map<FarmDestination, String> labels;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final destination in FarmDestination.values)
        if (actions.containsKey(destination) &&
            (destination != FarmDestination.agenda || session?.permissions?.allows('agenda.read') == true || session?.permissions?.allows('agenda.plan') == true) &&
            (destination != FarmDestination.users ||
                session?.canManageUsers == true))
          ListTile(
            key: ValueKey('navigation-${destination.name}'),
            leading: Icon(
              destination == FarmDestination.history
                  ? Icons.history
                  : destination == FarmDestination.users
                  ? Icons.people_outline
                  : Icons.chevron_right,
            ),
            title: Text(
              labels[destination] ?? farmDestinationLabels[destination]!,
            ),
            onTap: actions[destination],
          ),
    ],
  );
}
