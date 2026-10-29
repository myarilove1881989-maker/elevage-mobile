import 'package:flutter/foundation.dart';
import 'expense_business_date.dart';
import 'expense_consistent_catalog.dart';
import 'expense_input_contract.dart';
import 'expense_intention.dart';
import 'expense_intention_session.dart';
import 'expense_preparation.dart';
import 'expense_tablet_adapter.dart';
import 'outbox.dart';
import 'tablet_controller.dart';
import 'terrain_store.dart';

/// One screen lifetime, one original session, one immutable intention.
/// All persistence and sequence allocation remain in TabletController.declare.
class ExpenseFormController extends ChangeNotifier {
  final TabletController tablet;
  final ExpenseBusinessDate dates;
  late final ExpenseTabletSessionObserver observer;
  late final ExpenseIntentionCoordinator coordinator;
  ExpenseCapturedSession? _captured, _readCaptured;
  ExpenseTabletReadBridge? _bridge;
  ExpenseIntention? _original;
  Object? _originCache;
  String? _originalName;
  ExpenseCheckedCatalog? categories;
  List<ExpenseLotSelection> lots = const [];
  Map<String, ExpenseInputError> fieldErrors = const {};
  ExpenseDurableResult result = const ExpenseDurableResult(
    ExpenseDurableState.notRecorded,
  );
  bool busy = false, suspended = false, _disposed = false;
  String? error, dateError;
  bool get resultVisible => !suspended || _readCaptured != null;
  String? get operationId => coordinator.pendingOperationId;
  bool get editable =>
      !busy &&
      !suspended &&
      operationId == null &&
      categories != null &&
      _captured != null;

  ExpenseFormController(this.tablet, this.dates) {
    observer = ExpenseTabletSessionObserver(tablet);
    coordinator = ExpenseIntentionCoordinator(
      observe: observer.observe,
      utcClock: () => tablet.clock().toUtc(),
    );
    tablet.addListener(checkContext);
  }
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  void _check({bool validation = false}) {
    if (_disposed || suspended) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.suspended);
    }
    final captured = _captured;
    if (captured != null) {
      try {
        if (validation) {
          captured.checkForValidation(
            observer.observe(),
            tablet.clock().toUtc(),
          );
        } else {
          captured.checkIdentity(observer.observe());
        }
      } on ExpenseSessionException {
        suspended = true;
        _readCaptured = null;
        lots = const [];
        categories = null;
        fieldErrors = const {};
        error =
            'Session suspendue. Le brouillon est masqué. Aucune nouvelle déclaration ne sera créée.';
        rethrow;
      }
    }
  }

  void checkContext() {
    if (_disposed) return;
    if (suspended) {
      if (_readCaptured != null) {
        try {
          _readCaptured!.checkIdentity(observer.observe());
        } catch (_) {
          _readCaptured = null;
          _publish();
        }
      }
      return;
    }
    try {
      _check();
    } catch (_) {
      _publish();
    }
  }

  Future<void> load() async {
    if (busy || _disposed || suspended || operationId != null) return;
    busy = true;
    error = null;
    categories = null;
    lots = const [];
    _publish();
    try {
      _captured ??= observer.capture();
      _originCache ??= tablet.cache;
      _check(validation: true);
      _bridge ??= ExpenseTabletReadBridge(observer, _captured!);
      final cache = tablet.cache;
      if (cache is! TerrainStore) {
        throw StateError('Projections locales indisponibles.');
      }
      final catalog = await _bridge!.categories();
      _check(validation: true);
      final origin = ExpenseSelectionContext(
        farmId: _captured!.farmId,
        authorId: _captured!.authorId,
      );
      final parents = <String, OutboxEntry>{};
      var offset = 0;
      while (true) {
        final page = await _bridge!.lotCreatorsPage(offset: offset, limit: 50);
        _check(validation: true);
        if (page.isEmpty) break;
        for (final row in page) {
          final declaration = row.declaration;
          if (declaration['exploitation_id'] != origin.farmId ||
              declaration['device_id'] != _captured!.deviceId ||
              declaration['device_generation'] != _captured!.generation ||
              declaration['operation_type'] != 'CREATE' ||
              !{'ACHAT', 'NAISSANCE'}.contains(declaration['entity_type']) ||
              {'NOT_APPLIED', 'SUPERSEDED'}.contains(row.businessStatus)) {
            continue;
          }
          if (parents.containsKey(row.operationId)) {
            throw StateError('Registre ambigu.');
          }
          parents[row.operationId] = row;
        }
        offset += page.length;
      }
      final selections = <ExpenseLotSelection>[];
      final references = <String>{};
      offset = 0;
      while (true) {
        _check(validation: true);
        final page = await (cache as TerrainStore).projectedPage(
          'lots',
          offset: offset,
          limit: 50,
        );
        _check(validation: true);
        if (page.isEmpty) break;
        for (final row in page) {
          ExpenseLotSelection lot;
          try {
            lot = ExpenseLotSelection.fromProjectedRow(
              row,
              origin: origin,
              parentDeclaration: parents[row['dependency']]?.declaration,
              deviceId: _captured!.deviceId,
              generation: _captured!.generation,
            );
          } on ExpensePreparationException {
            // An inaccessible reference cannot authorize a declaration and
            // must not hide independent valid lots from this farm.
            continue;
          }
          if (!references.add(canonicalDeclaration(lot.reference))) {
            throw StateError('Lots ambigus.');
          }
          selections.add(lot);
        }
        offset += page.length;
      }
      _check(validation: true);
      categories = catalog;
      lots = List.unmodifiable(selections);
    } catch (e) {
      error ??= expenseFormError(e);
    } finally {
      busy = false;
      _publish();
    }
  }

  Future<void> submit({
    required ExpenseLotSelection? lot,
    required int? categoryId,
    required String amount,
    String? note,
    required ExpenseBusinessDay day,
  }) async {
    if (!editable || _disposed) return;
    // Synchronous exclusion before ANY asynchronous boundary.
    busy = true;
    error = null;
    fieldErrors = const {};
    dateError = null;
    _publish();
    var crossedBoundary = false;
    try {
      _check(validation: true);
      if (_captured == null || categories == null) {
        throw StateError('Chargez les références locales.');
      }
      final input = ExpenseInputContract.validate(
        lotRef: lot?.reference,
        categoryId: categoryId,
        amount: amount,
        note: note,
      );
      if (!input.isValid) {
        fieldErrors = input.errors;
        return;
      }
      if (!lots.contains(lot)) throw StateError('Référence de lot ambiguë.');
      final prepared = ExpensePreparation.compose(
        currentContext: ExpenseSelectionContext(
          farmId: _captured!.farmId,
          authorId: _captured!.authorId,
        ),
        lot: lot!,
        categories: categories!.catalog,
        categoryId: categoryId!,
        amount: amount,
        note: note,
        day: day,
        dates: dates,
        nowUtc: tablet.clock().toUtc(),
      );
      _original = coordinator.begin(prepared);
      _originalName ??= tablet.selectedName;
      final parameters = ExpenseDeclarationParameters.reserve(coordinator);
      final currentCategories = await _bridge!.categories();
      _check(validation: true);
      if (currentCategories.catalog.select(categoryId).name !=
          prepared.category.name) {
        throw ExpensePreparationException(ExpensePreparationError.invalidCache);
      }
      _check(validation: true);
      parameters.origin.checkForValidation(
        observer.observe(),
        tablet.clock().toUtc(),
      );
      coordinator.markUncertain();
      result = _original!.result;
      crossedBoundary = true;
      await tablet.declare(
        entityType: parameters.entityType,
        operationType: parameters.operationType,
        payload: parameters.payload,
        businessOccurredAt: parameters.businessOccurredAt,
        operationId: parameters.operationId,
        localEntityId: parameters.localEntityId,
        dependencies: parameters.dependencies,
        expectedServerVersion: parameters.expectedServerVersion,
      );
      _check();
      result = await coordinator.inspect(_bridge!.ledgerPage);
      _check();
    } catch (e) {
      error ??= expenseFormError(e);
      if (e is ExpenseDateException) dateError = expenseFormError(e);
      if (crossedBoundary && !suspended && !_disposed) {
        try {
          _check();
          result = await coordinator.inspect(_bridge!.ledgerPage);
          _check();
        } catch (readError) {
          error = expenseFormError(readError);
        }
      } else if (!crossedBoundary && _original != null && !suspended) {
        coordinator.releaseUnsubmittedValidation();
      }
    } finally {
      busy = false;
      _publish();
    }
  }

  /// Explicit human PIN action only; reuses the EXISTING unlock method.
  /// No preparation, grant issuance, renewal or business declaration occurs.
  Future<void> reopenOriginal(String pin,{bool personalCode=false}) async {
    if (busy || _disposed || !suspended || _original == null) return;
    busy = true;
    error = null;
    _readCaptured = null;
    _publish();
    try {
      final origin = _original!.context;
      void samePreparedContext() {
        final profiles = tablet.profiles
            .where((p) => p['user_id'] == origin.authorId)
            .toList();
        if (_disposed ||
            tablet.isDisposed ||
            !identical(_originCache, tablet.cache) ||
            tablet.farmId != origin.farmId ||
            tablet.deviceId != origin.deviceId ||
            tablet.generation != origin.generation ||
            profiles.length != 1 ||
            profiles.single['membership_id'] != origin.membershipId ||
            profiles.single['rights_version'] != origin.rightsVersion ||
            profiles.single['write_generation'] != origin.generation ||
            profiles.single['display_name'] != _originalName) {
          throw const ExpenseSessionException(
            ExpenseSessionFailure.contextChanged,
          );
        }
      }

      samePreparedContext();
      final epoch = tablet.sessionEpoch;
      final stored = await tablet.api.loadLocalGrant(
        farmId: origin.farmId,
        userId: origin.authorId,
      );
      samePreparedContext();
      if (tablet.sessionEpoch != epoch || stored.token != origin.grant.token) {
        throw const ExpenseSessionException(
          ExpenseSessionFailure.contextChanged,
        );
      }
      await tablet.unlockProfile(origin.authorId, _originalName!, pin,personalCode:personalCode);
      samePreparedContext();
      final reopened = observer.capture();
      final bridge = ExpenseTabletReadBridge(observer, reopened);
      final recovered = await bridge.recoverOriginal(_original!, coordinator);
      reopened.checkIdentity(observer.observe());
      _readCaptured = reopened;
      result = recovered;
      // suspended remains true, and submit remains disabled forever.
    } catch (e) {
      error = expenseFormError(e);
    } finally {
      busy = false;
      _publish();
    }
  }

  /// Explicit register consultation, including read-only original-grant reopen.
  Future<void> verify() async {
    if (busy || _disposed || _original == null) return;
    busy = true;
    error = null;
    _publish();
    try {
      if (suspended) {
        _readCaptured = null;
        final reopened = observer.capture();
        final bridge = ExpenseTabletReadBridge(observer, reopened);
        final recovered = await bridge.recoverOriginal(_original!, coordinator);
        reopened.checkIdentity(observer.observe());
        _readCaptured = reopened;
        result = recovered; // Never reactivate the suspended intention.
      } else {
        _check();
        result = await coordinator.inspect(_bridge!.ledgerPage);
        _check();
      }
    } catch (e) {
      error ??= expenseFormError(e);
    } finally {
      busy = false;
      _publish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    tablet.removeListener(checkContext);
    super.dispose();
  }
}

String expenseStatusText(ExpenseDurableResult result) {
  switch (result.state) {
    case ExpenseDurableState.notRecorded:
      return 'Brouillon non enregistré';
    case ExpenseDurableState.uncertain:
      return 'Résultat incertain — vérifier ultérieurement, sans nouvelle déclaration';
    case ExpenseDurableState.durable:
      return result.entry?.transportStatus == 'SERVER_RECEIVED' &&
              result.entry?.receivedAt != null
          ? 'Reçu par le serveur — confirmation en attente'
          : 'Enregistré sur cet appareil — confirmation serveur en attente';
    case ExpenseDurableState.confirmed:
      return 'Confirmé / appliqué';
    case ExpenseDurableState.reconciliation:
      return 'À rapprocher';
    case ExpenseDurableState.notApplied:
      return 'Non appliqué';
  }
}

String expenseFormError(Object error) {
  if (error is ExpenseSessionException) {
    return 'Ouvrez votre profil opérateur avec votre PIN. La saisie des dépenses nécessite une autorisation individuelle à jour ; reconnectez-vous pour la renouveler ou demandez au propriétaire le droit de créer des dépenses.';
  }
  if (error is ExpenseDateException) {
    return 'Date métier invalide ou future (Europe/Paris).';
  }
  if (error is ExpensePreparationException) {
    return 'Références locales absentes, ambiguës ou hors contexte. Rechargez explicitement les références.';
  }
  if (error is ExpenseIntentionException) {
    return 'Intention suspendue ou déjà réservée. Consultez le registre sans recréer la dépense.';
  }
  return 'Lecture ou enregistrement interrompu. Consultez le statut et vérifiez le registre ; aucune nouvelle déclaration automatique.';
}
