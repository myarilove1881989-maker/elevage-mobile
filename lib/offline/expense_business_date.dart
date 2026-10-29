import 'package:timezone/timezone.dart' as tz;

enum ExpenseDateError { invalidDate, futureDate, utcRequired, wrongTimeZone }

class ExpenseDateException implements Exception {
  final ExpenseDateError code;
  const ExpenseDateException(this.code);
}

/// A calendar date, not a phone-local DateTime and not an event timestamp.
class ExpenseBusinessDay {
  final int year;
  final int month;
  final int day;

  ExpenseBusinessDay(this.year, this.month, this.day) {
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      throw const ExpenseDateException(ExpenseDateError.invalidDate);
    }
    final normalized = DateTime.utc(year, month, day);
    if (year < 1 ||
        year > 9999 ||
        normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw const ExpenseDateException(ExpenseDateError.invalidDate);
    }
  }
}

/// The caller supplies an initialized Europe/Paris location. This class does
/// not initialize timezone globals or read the clock/device timezone.
class ExpenseBusinessDate {
  final tz.Location location;
  ExpenseBusinessDate(this.location) {
    if (location.name != 'Europe/Paris') {
      throw const ExpenseDateException(ExpenseDateError.wrongTimeZone);
    }
  }

  DateTime representativeUtc(
    ExpenseBusinessDay selected, {
    required DateTime nowUtc,
  }) {
    if (!nowUtc.isUtc) {
      throw const ExpenseDateException(ExpenseDateError.utcRequired);
    }
    final today = tz.TZDateTime.from(nowUtc, location);
    final selectedDay = DateTime.utc(
      selected.year,
      selected.month,
      selected.day,
    );
    if (selectedDay.isAfter(DateTime.utc(today.year, today.month, today.day))) {
      throw const ExpenseDateException(ExpenseDateError.futureDate);
    }
    return tz.TZDateTime(
      location,
      selected.year,
      selected.month,
      selected.day,
      12,
    ).toUtc();
  }

  ExpenseBusinessDay businessDayOf(DateTime instantUtc) {
    if (!instantUtc.isUtc) {
      throw const ExpenseDateException(ExpenseDateError.utcRequired);
    }
    final local = tz.TZDateTime.from(instantUtc, location);
    return ExpenseBusinessDay(local.year, local.month, local.day);
  }
}
