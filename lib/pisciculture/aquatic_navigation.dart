import 'package:flutter/material.dart';

class AquaticMenuEntry {
  const AquaticMenuEntry(this.title, this.icon, this.destination);
  final String title, destination;
  final IconData icon;
}

const aquaticMenuGroups = <String, List<AquaticMenuEntry>>{
  'management_hub': [
    AquaticMenuEntry('Alimentation', Icons.grass_outlined, 'feeding'),
    AquaticMenuEntry('Santé', Icons.health_and_safety_outlined, 'health'),
    AquaticMenuEntry('Reproduction', Icons.autorenew, 'breeding'),
  ],
  'purchases_hub': [
    AquaticMenuEntry(
      'Poissons et alevins',
      Icons.shopping_bag_outlined,
      'new_cohort',
    ),
  ],
  'expenses_hub': [
    AquaticMenuEntry(
      'Dépenses',
      Icons.account_balance_wallet_outlined,
      'new_expense',
    ),
    AquaticMenuEntry(
      'Achats de consommables',
      Icons.inventory_2_outlined,
      'feed_purchases',
    ),
  ],
  'production_hub': [
    AquaticMenuEntry('Cohortes', Icons.layers_outlined, 'cohorts'),
    AquaticMenuEntry(
      'Croissance et pesées',
      Icons.monitor_weight_outlined,
      'weights',
    ),
    AquaticMenuEntry('Alimentation', Icons.grass_outlined, 'feeding'),
    AquaticMenuEntry('Récoltes', Icons.set_meal_outlined, 'commerce'),
    AquaticMenuEntry('Reproduction', Icons.autorenew, 'breeding'),
  ],
  'technical_hub': [
    AquaticMenuEntry('Installations', Icons.pool_outlined, 'installations'),
    AquaticMenuEntry('Qualité de l’eau', Icons.water_drop_outlined, 'water'),
    AquaticMenuEntry('Règles et seuils', Icons.tune, 'rules'),
    AquaticMenuEntry('Santé', Icons.health_and_safety_outlined, 'health'),
  ],
  'movements_hub': [
    AquaticMenuEntry('Transferts', Icons.swap_horiz, 'transfer_form'),
    AquaticMenuEntry(
      'Mortalités et pertes',
      Icons.warning_amber_outlined,
      'stock',
    ),
    AquaticMenuEntry(
      'Corrections d’inventaire',
      Icons.fact_check_outlined,
      'stock_inventory',
    ),
    AquaticMenuEntry('Ventes', Icons.point_of_sale_outlined, 'commerce_sale'),
  ],
  'billing_hub': [
    AquaticMenuEntry(
      'Factures',
      Icons.receipt_long_outlined,
      'commerce_invoices',
    ),
    AquaticMenuEntry('Clients', Icons.people_outline, 'commerce_clients'),
    AquaticMenuEntry('Paiements', Icons.payments_outlined, 'commerce_payments'),
    AquaticMenuEntry(
      'Soldes clients',
      Icons.account_balance_wallet_outlined,
      'commerce_balances',
    ),
  ],
};
const aquaticMenuTitles = {
  'management_hub': 'Gestion',
  'purchases_hub': 'Achats',
  'expenses_hub': 'Dépenses',
  'production_hub': 'Production',
  'technical_hub': 'Technique',
  'movements_hub': 'Mouvements',
  'billing_hub': 'Facturation',
};
