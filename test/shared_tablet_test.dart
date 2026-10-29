import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:app_elevage/offline/expense_business_date.dart';
import 'package:app_elevage/offline/expense_form_controller.dart';
import 'package:app_elevage/offline/expense_intention.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'offline_fine_permissions_test.dart' show fineGrant;
import 'seven_day_integration_test.dart' show SevenDayHarness;

class SharedTabletHarness extends SevenDayHarness {
  @override
  Map<String, dynamic> receipt(Map<String, dynamic> operation) {
    final result = super.receipt(operation);
    if (operation['entity_type'] == 'VENTE_ANIMAUX') {
      result['stock_snapshots'] = [
        {
          'id': 42,
          'nom': 'Porcs démonstration',
          'exploitation': 1,
          'stock':
              100 -
              originals.values
                  .where((op) => op['entity_type'] == 'VENTE_ANIMAUX')
                  .fold<int>(
                    0,
                    (sum, op) => sum + (op['payload']['quantite'] as int),
                  ),
          'stock_oeufs': 0,
          'confirmed_business_revision': originals.length,
        },
      ];
    }
    return result;
  }

  Future<void> jean() async {
    late Map<String, dynamic> response;
    final grant = await fineGrant(
      user: 3,
      expectedUser: 3,
      codes: ['finance.read', 'expenses.create'],
      now: now,
      duration: const Duration(days: 7),
      issued: (r) => response = r,
    );
    await db.saveOperatorProfile(grant, 'Jean');
    await LocalOperatorSessions(
      store: secrets,
      namespace: Uri.encodeComponent(SevenDayHarness.base),
      farmId: 1,
      deviceId: 7,
      generation: 1,
      clock: () => now,
    ).enroll(grant, '654321');
    secrets.values['offline_grant_${Uri.encodeComponent(SevenDayHarness.base)}_1_3'] =
        jsonEncode({
          'token': grant.token,
          'public_key': response['public_key'],
          'key_id': response['key_id'],
          'device_id': 7,
          'generation': 1,
          'rights_version': 1,
        });
    tablet.profiles = await db.operatorProfiles();
  }

  Future<void> sale({String? id, Future<void> Function()? project}) async {
    await tablet.declare(
      entityType: 'VENTE_ANIMAUX',
      operationType: 'CREATE',
      payload: {
        'lot_ref': {'server_id': 42},
        'client_ref': {'server_id': 11},
        'quantite': 10,
        'prix_unitaire': '15.00',
      },
      businessOccurredAt: now,
      operationId: id,
      project: project,
    );
  }
}

void main() {
  tzdata.initializeTimeZones();
  late SharedTabletHarness h;
  setUp(() async {
    h = SharedTabletHarness();
    await h.start();
    await h.jean();
    h.down = true;
    await h.db.replaceConfirmedCache('lots', [
      {
        'id': 42,
        'nom': 'Porcs démonstration',
        'exploitation': 1,
        'stock': 100,
        'stock_oeufs': 0,
        'confirmed_business_revision': 0,
      },
    ]);
    await h.db.replaceConfirmedCache('expense_categories', [
      {'id': 1, 'nom': 'Transport'},
    ]);
  });
  tearDown(() async {
    await h.close();
  });

  test(
    'Paul sale shares 90 with Jean, personal rights and authors survive reopen and retry',
    () async {
      await h.sale();
      final sale = (await h.db.listOutbox()).single;
      expect(sale.authorId, 2);
      expect(
        (await h.tablet.readPage('lots')).single['data'],
        containsPair('projected_stock', 90),
      );
      h.tablet.lock();
      await expectLater(
        h.tablet.unlockProfile(3, 'Jean', '123456'),
        throwsStateError,
      );
      await h.tablet.unlockProfile(3, 'Jean', '654321');
      final stock = (await h.tablet.readPage('lots')).single['data'];
      expect(stock, containsPair('stock', 100));
      expect(stock, containsPair('projected_stock', 90));
      expect(h.tablet.outboxRows, isEmpty);
      await expectLater(h.sale(), throwsStateError);
      await h.expense();
      expect(h.tablet.outboxRows.every((e) => e.authorId == 3), isTrue);
      final originals = (await h.db.listOutbox())
          .map((e) => e.declaration)
          .toList();
      await h.reopen();
      await h.tablet.unlockProfile(3, 'Jean', '654321');
      expect(
        (await h.tablet.readPage('lots')).single['data'],
        containsPair('projected_stock', 90),
      );
      expect(
        (await h.db.listOutbox()).map((e) => e.declaration).toList(),
        originals,
      );
      h.down = false;
      h.lost = true;
      h.now = h.now.add(const Duration(minutes: 1));
      await h.reconnect();
      h.network!.add(false);
      h.now = h.now.add(const Duration(minutes: 6));
      await h.reconnect();
      expect(h.effects, hasLength(2));
      expect(h.originals, hasLength(2));
      expect(
        (await h.db.listOutbox()).every((e) => e.businessStatus == 'CONFIRMED'),
        isTrue,
      );
      expect(
        (await h.db.listOutbox()).map((e) => e.declaration).toList(),
        originals,
      );
      final confirmed = (await h.tablet.readPage('lots')).single['data'];
      expect(confirmed, containsPair('stock', 90));
      expect(confirmed, containsPair('projected_stock', 90));
    },
  );

  for (final connected in [false, true]) {
    test(
      'Paul HTTP identity is not inherited on Paul Jean Paul PIN switch; connected=$connected',
      () async {
        h.down = !connected;
        h.authenticate(2);
        h.tablet.lock();
        await h.tablet.unlockProfile(3, 'Jean', '654321');
        expect(h.api.personal, isNull);
        final form = ExpenseFormController(
          h.tablet,
          ExpenseBusinessDate(tz.getLocation('Europe/Paris')),
        );
        try {
          await form.load();
          expect(form.error, isNull);
          expect(form.editable, isTrue);
          await form.submit(
            lot: form.lots.single,
            categoryId: 1,
            amount: '2.00',
            day: ExpenseBusinessDate(
              tz.getLocation('Europe/Paris'),
            ).businessDayOf(h.now),
          );
          expect(form.result.state, ExpenseDurableState.durable);
          expect((await h.db.listOutbox()).single.authorId, 3);
        } finally {
          form.dispose();
        }
        await expectLater(h.tablet.refreshCache(), throwsA(anything));
        expect(h.capabilityReads, 0);
        h.tablet.lock();
        await h.tablet.unlockProfile(2, 'Employé fictif 2', '123456');
        expect(h.api.personal, isNull);
        expect(h.tablet.outboxRows, isEmpty);
      },
    );
  }

  test(
    'two pending writes roll back during PIN switch and neither is reattributed',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final first = h.sale(
        project: () async {
          entered.complete();
          await release.future;
        },
      );
      final firstCheck = expectLater(first, throwsStateError);
      await entered.future;
      final second = h.sale();
      final secondCheck = expectLater(second, throwsStateError);
      h.tablet.lock();
      release.complete();
      await Future.wait([firstCheck, secondCheck]);
      await h.tablet.unlockProfile(3, 'Jean', '654321');
      expect(await h.db.listOutbox(), isEmpty);
      await h.expense();
      expect((await h.db.listOutbox()).single.authorId, 3);
    },
  );

  test(
    'same UUID is idempotent while distinct UUIDs represent distinct human entries',
    () async {
      const id = '00000000-0000-4000-8000-000000000123';
      await Future.wait([h.sale(id: id), h.sale(id: id)]);
      expect(await h.db.listOutbox(), hasLength(1));
      await h.sale();
      expect(await h.db.listOutbox(), hasLength(2));
      expect(
        (await h.db.projectedPage('lots')).single['data'],
        containsPair('projected_stock', 80),
      );
    },
  );
}
