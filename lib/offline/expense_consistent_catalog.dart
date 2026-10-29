import 'expense_preparation.dart';
import 'expense_intention_session.dart';

enum ExpenseCatalogConsistency { unverified, verifiedByVersion }

class ExpenseCheckedCatalog {
  final ExpenseCategoryCatalog catalog;
  final ExpenseCatalogConsistency consistency;
  const ExpenseCheckedCatalog(this.catalog, this.consistency);
}

/// Optional readVersion must describe the entire local category collection,
/// change on every replacement, and be monotonic/non-reusable (no ABA).
/// Existing APIs expose no such category revision: default is UNVERIFIED.
class ExpenseConsistentCatalog {
  static Future<ExpenseCheckedCatalog> read({
    required ExpenseCapturedSession captured,
    required ExpenseSessionObservation Function() observe,
    required ExpenseCachedPageReader readPage,
    required ExpenseCacheFreshness freshness,
    Future<String?> Function()? readVersion,
    int pageSize = 50,
  }) async {
    String? baseline;
    bool initialized = false;
    Future<void> checkpoint() async {
      captured.checkIdentity(observe());
      final version = readVersion == null ? null : await readVersion();
      captured.checkIdentity(observe());
      if (!initialized) {
        baseline = version;
        initialized = true;
      } else if (baseline != version) {
        throw ExpensePreparationException(ExpensePreparationError.invalidCache);
      }
    }

    await checkpoint();
    final origin = ExpenseSelectionContext(
      farmId: captured.farmId,
      authorId: captured.authorId,
    );
    final catalog = await ExpenseCategoryCatalog.readAll(
      origin: origin,
      currentContext: () {
        captured.checkIdentity(observe());
        return origin;
      },
      freshness: freshness,
      pageSize: pageSize,
      readPage: (collection, {required offset, required limit}) async {
        await checkpoint();
        final rows = await readPage(collection, offset: offset, limit: limit);
        await checkpoint();
        return rows;
      },
    );
    await checkpoint();
    return ExpenseCheckedCatalog(
      catalog,
      baseline == null || baseline!.isEmpty
          ? ExpenseCatalogConsistency.unverified
          : ExpenseCatalogConsistency.verifiedByVersion,
    );
  }
}
