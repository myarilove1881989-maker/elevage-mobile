import 'package:flutter/material.dart';
import '../offline/expense_business_date.dart';
import '../offline/expense_preparation.dart';
import '../offline/expense_input_contract.dart';

String? expenseFieldError(ExpenseInputError? error) => switch (error) {
  null => null,
  ExpenseInputError.required => 'Champ obligatoire.',
  ExpenseInputError.precision => 'Deux décimales au maximum.',
  ExpenseInputError.nonPositive => 'Montant supérieur à zéro requis.',
  ExpenseInputError.tooLarge => 'Montant trop élevé.',
  ExpenseInputError.tooLong => '255 caractères au maximum.',
  ExpenseInputError.invalid => 'Saisie invalide.',
};

/// The same input controls for HTTP and signed offline expense submission.
class ExpenseFields extends StatelessWidget {
  const ExpenseFields({
    super.key,
    required this.lots,
    required this.categories,
    required this.categoryKey,
    required this.lot,
    required this.categoryId,
    required this.amount,
    required this.note,
    required this.day,
    required this.editable,
    required this.fieldError,
    required this.onLot,
    required this.onCategory,
    required this.chooseDate,
  });
  final List<ExpenseLotSelection> lots;
  final List<(int, String)> categories;
  final Object? categoryKey;
  final ExpenseLotSelection? lot;
  final int? categoryId;
  final TextEditingController amount, note;
  final ExpenseBusinessDay day;
  final bool editable;
  final String? Function(String) fieldError;
  final ValueChanged<ExpenseLotSelection?> onLot;
  final ValueChanged<int?> onCategory;
  final VoidCallback chooseDate;
  @override
  Widget build(BuildContext context) => Column(
    spacing: 14,
    children: [
      DropdownButtonFormField<ExpenseLotSelection>(
        isExpanded: true,
        key: ValueKey(lots),
        initialValue: lot,
        decoration: InputDecoration(
          labelText: 'Lot',
          errorText: fieldError('lot_ref'),
        ),
        items: [
          for (final value in lots)
            DropdownMenuItem(
              value: value,
              child: Text(
                '${value.name}${value.isFinished ? ' — lot terminé' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: editable ? onLot : null,
      ),
      DropdownButtonFormField<int>(
        isExpanded: true,
        key: ValueKey(categoryKey),
        initialValue: categoryId,
        decoration: InputDecoration(
          labelText: 'Catégorie',
          errorText: fieldError('categorie_id'),
        ),
        items: [
          for (final value in categories)
            DropdownMenuItem(value: value.$1, child: Text(value.$2,maxLines:1,overflow:TextOverflow.ellipsis)),
        ],
        onChanged: editable ? onCategory : null,
      ),
      TextField(
        key: const Key('expense-amount'),
        controller: amount,
        enabled: editable,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Montant exact',
          errorText: fieldError('montant'),
        ),
      ),
      TextField(
        key: const Key('expense-note'),
        controller: note,
        enabled: editable,
        decoration: InputDecoration(
          labelText: 'Note facultative',
          errorText: fieldError('note'),
        ),
      ),
      TextButton(
        onPressed: null,
        child: Text(
          'Date : ${day.day}/${day.month}/${day.year}',
        ),
      ),
    ],
  );
}
