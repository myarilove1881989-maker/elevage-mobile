import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/farm_session.dart';
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/services/operation_history.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';
import 'package:app_elevage/widgets/operation_history_list.dart';
import 'package:app_elevage/widgets/cancellation_dialog.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/sync_state.dart';

FarmSession session(String role) {
  final rights = PermissionContract.decode(
    {
      'version': 1,
      'user': 1,
      'exploitation': 2,
      'role': role,
      'rights_version': 1,
      'permissions': [
        'finance.read',
        'history.read',
        if (role == 'OWNER') 'users.manage',
      ],
    },
    userId: 1,
    farmId: 2,
    role: role,
    rightsVersion: 1,
  );
  return FarmSession(
    userId: 1,
    farmId: 2,
    role: role,
    permissions: rights,
    origin: SessionOrigin.personalHttp,
    network: NetworkState.unavailable,
    sync: const SyncSummary(pending: 1),
  );
}

void main() {
  setUpAll(() async {
    for (final font in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final bytes = await File(
        '${Platform.environment['FLUTTER_ROOT']??'../flutter-sdk'}/bin/cache/artifacts/material_fonts/${font.value}',
      ).readAsBytes();
      final loader = FontLoader(font.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  test(
    'expense cancellation retains caller UUID and makes one request, without REST retry',
    () async {
      var calls = 0;
      const uuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final api = ApiService(
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(request.url.path, endsWith('/depenses/cancel/4/'));
          expect(jsonDecode(request.body), {
            'reason': 'Synthetic reason',
            'operation_uuid': uuid,
          });
          return http.Response(
            jsonEncode({'id': 9, 'original_id': 4, 'status': 'CANCELLED'}),
            200,
          );
        }),
      );
      ApiService.token = 'synthetic-test';
      final result = await api.cancelExpense(
        4,
        reason: ' Synthetic reason ',
        operationUuid: uuid,
      );
      expect(result['original_id'], 4);
      expect(calls, 1);
      await expectLater(
        api.cancelExpense(4, reason: ' ', operationUuid: uuid),
        throwsArgumentError,
      );
      expect(calls, 1);
      api.close();
      ApiService.token = null;
    },
  );
  test(
    'typed identity rejects cross farm and does not activate fine offline permissions',
    () {
      expect(
        () => FarmSession(
          userId: 1,
          farmId: 3,
          role: 'OWNER',
          permissions: session('OWNER').permissions,
          origin: SessionOrigin.personalHttp,
          network: NetworkState.unknown,
          sync: const SyncSummary(),
        ),
        throwsStateError,
      );
      expect(session('OWNER').canCancelTask, isTrue);
      expect(session('OPERATEUR').canCancelTask, isFalse);
      expect(session('OWNER').fineOfflineRightsActivated, isFalse);
    },
  );
  test(
    'changed session does not confirm an expense cancellation for another profile',
    () async {
      ApiService.token = 'synthetic-first';
      var calls = 0;
      final api = ApiService(
        client: MockClient((request) async {
          calls++;
          ApiService.token = 'synthetic-other';
          return http.Response(
            jsonEncode({'id': 9, 'original_id': 4, 'status': 'CANCELLED'}),
            200,
          );
        }),
      );
      await expectLater(
        api.cancelExpense(
          4,
          reason: 'Synthetic',
          operationUuid: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        ),
        throwsStateError,
      );
      expect(calls, 1);
      api.close();
      ApiService.token = null;
    },
  );
  test(
    'local pending and received records never display confirmed before business outcome',
    () {
      OutboxEntry entry(String transport, String business) => OutboxEntry(
        declaration: {
          'client_operation_id': 'synthetic-uuid',
          'author_user_id': 1,
          'local_sequence': 1,
          'entity_type': 'DEPENSE',
          'payload': {'lot_id': 2, 'montant': '12.00'},
          'business_occurred_at': '2026-10-12',
          'local_recorded_at': '2026-10-12',
        },
        transportStatus: transport,
        businessStatus: business,
        attemptCount: 0,
        lastError: '',
      );
      expect(
        OperationHistoryItem.local(entry('LOCAL_PENDING', 'UNREVIEWED')).status,
        contains('attente'),
      );
      expect(
        OperationHistoryItem.local(
          entry('SERVER_RECEIVED', 'UNREVIEWED'),
        ).status,
        contains('confirmation en attente'),
      );
      expect(
        OperationHistoryItem.local(
          entry('SERVER_RECEIVED', 'CONFIRMED'),
        ).status,
        'Confirmé par le serveur',
      );
      expect(
        OperationHistoryItem.local(
          entry('SERVER_RECEIVED', 'NEEDS_RECONCILIATION'),
        ).status,
        contains('vérification'),
      );
      expect(
        OperationHistoryItem.local(
          entry('SERVER_RECEIVED', 'NOT_APPLIED'),
        ).status,
        contains('pas été appliquée'),
      );
      expect(
        OperationHistoryItem.local(
          entry('SERVER_RECEIVED', 'SUPERSEDED'),
        ).status,
        contains('historique conservé'),
      );
    },
  );
  test(
    'composite cancellation preserves reason author original compensation and groups UUID',
    () {
      final result = serverHistory([
        {
          'id': 1,
          'correlation_id': 'same',
          'entity_type': 'core.depense',
          'entity_id': '4',
          'actor_user_id': 7,
          'after_data': {
            'lot_id': 2,
            'montant': '12.00',
            'voided_at': '2026-10-12',
            'created_by_id': 3,
            'date': '2026-10-10',
          },
          'reason_text': 'Erreur synthétique',
        },
        {
          'id': 2,
          'correlation_id': 'same',
          'entity_type': 'core.expensecancellation',
          'entity_id': '9',
          'actor_user_id': 7,
          'after_data': {'expense_id': 4, 'reason': 'Erreur synthétique'},
          'reason_code': 'EXPENSE_CANCELLED',
        },
      ]);
      expect(result.length, 1);
      expect(
        result.single.author,
        'Utilisateur 3 • événement par Utilisateur 7',
      );
      expect(result.single.businessDate, '2026-10-10');
      expect(result.single.reason, 'Erreur synthétique');
      expect(result.single.status, contains('Annulée'));
      expect(result.single.original, 'Dépense 4');
      expect(result.single.compensation, 'Annulation 9');
    },
  );
  // Outcome state, rather than mere server receipt or an old voided effect,
  // controls the current status of a grouped declaration.
  test(
    'server history keeps reconciliation pending and current corrected outcome confirmed',
    () {
      final items = serverHistory([
        {
          'id': 3,
          'operation_id': 'pending',
          'entity_type': 'core.terrainoutcome',
          'actor_user_id': 1,
          'after_data': {'business_status': 'NEEDS_RECONCILIATION'},
        },
        {
          'id': 2,
          'operation_id': 'corrected',
          'entity_type': 'core.terrainoutcome',
          'actor_user_id': 1,
          'after_data': {'business_status': 'CONFIRMED'},
        },
        {
          'id': 1,
          'operation_id': 'corrected',
          'entity_type': 'core.depense',
          'actor_user_id': 1,
          'after_data': {'voided_at': '2026-10-10'},
        },
      ]);
      expect(items.length, 2);
      expect(items.first.status, contains('vérification'));
      expect(items.last.status, 'Confirmé par le serveur');
    },
  );
  for (final size in [
    const Size(360, 740),
    const Size(740, 360),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets('shared navigation and read-only cancelled history at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var selected = false;
      final boundary = GlobalKey();
      final item = OperationHistoryItem(
        identity: 'synthetic-uuid',
        author: 'Employé synthétique',
        type: 'Dépense',
        status: 'Annulée — original conservé',
        businessDate: '2026-10-12',
        recordedDate: '2026-10-12',
        details: '12.00',
        reason: 'Correction synthétique',
        original: 'Dépense 4',
        compensation: 'Annulation 9',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: ListView(
                children: [
                  FarmNavigation(
                    session: session('OWNER'),
                    actions: {
                      FarmDestination.history: () => selected = true,
                      FarmDestination.users: () {},
                    },
                  ),
                  OperationHistoryList(items: [item]),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Historique'));
      expect(selected, isTrue);
      expect(find.text('Gestion des utilisateurs'), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.textContaining('Correction synthétique'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size == const Size(1280, 800)) {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/offline-mission-history-synthetic.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FarmNavigation(
              session: session('OPERATEUR'),
              actions: {
                FarmDestination.users: () {},
                FarmDestination.history: () {},
              },
            ),
          ),
        ),
      );
      expect(find.text('Gestion des utilisateurs'), findsNothing);
    });
  }
  testWidgets(
    'cancellation requires explicit confirmation and nonblank reason',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await confirmCancellation(
                    context,
                    'Annuler cette tâche ?',
                  );
                },
                child: const Text('Annuler'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer l’annulation'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Indiquez le motif.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        '  Motif synthétique  ',
      );
      await tester.tap(find.text('Confirmer l’annulation'));
      await tester.pumpAndSettle();
      expect(result, 'Motif synthétique');
      expect(tester.takeException(), isNull);
    },
  );
}
