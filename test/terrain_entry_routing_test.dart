import 'package:app_elevage/screens/add_achat_screen.dart';
import 'package:app_elevage/screens/add_mouvement_screen.dart';
import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/terrain_entry_gate.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/screens/growth_tracking_screen.dart';
import 'package:app_elevage/widgets/operation_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'production_tracking_test.dart' show testApp;

class RoutingApi extends ApiService {
  Map<String,Object>? purchase,weight;
  @override
  Future<bool> createAchat({required String nomLot,required int especeId,required int quantite,
    required double prixTotal,required double prixUnitaire,required DateTime date,
    String typeProduction='CHAIR',String statutProduction='ELEVAGE',DateTime? dateNaissance,
    int? ageArriveeSemaines,DateTime? dateDebutPonte}) async {
    writes++;purchase={'nom':nomLot,'quantite':quantite,'total':prixTotal,'unitaire':prixUnitaire};return true;
  }
  @override
  Future<Map<String,dynamic>> createProductionWeight({required int lotId,required DateTime weighedAt,
    required int animalsWeighed,required double sampleWeightKg,String note=''}) async {
    writes++;weight={'lot':lotId,'nombre':animalsWeighed,'poids':sampleWeightKg};return {'id':50};
  }
  bool policy = true, unavailable = false;
  String role = 'OPERATEUR';
  List<String> rights = [
    'purchases.create',
    'births.create',
    'feed.create',
    'weights.create',
  ];
  int reads = 0, writes = 0;
  @override
  Future<dynamic> get(String endpoint) async {
    expect(endpoint, '/me/capabilities/');
    if (unavailable) throw const ApiConnectionException();
    return {
      'user': 2,
      'exploitation': 1,
      'role': role,
      'offline_policy_enabled': policy,
      'membership': {'version': 1},
      'permission_contract': {
        'version': 1,
        'user': 2,
        'exploitation': 1,
        'role': role,
        'rights_version': 1,
        'permissions': ['finance.read', ...rights],
      },
    };
  }

  @override
  Future<List<dynamic>> getEspeces() async {
    reads++;
    return [
      for (final name in [
        'Poulet',
        'Dinde',
        'Canard',
        'Pintade',
        'Porc',
        'Bovin',
        'Mouton',
        'Chèvre',
        'Lapin',
        'Poisson',
      ])
        {'id': reads++, 'nom': name},
    ];
  }

  @override
  Future<List<dynamic>> getLots() async {
    reads++;
    return [];
  }

  @override
  Future<List<dynamic>> getClients() async {
    reads++;
    return [];
  }

  @override
  Future<Map<String, dynamic>> getLotDetail(int id) async {
    reads++;
    return {'depenses': []};
  }

  @override
  Future<Map<String, dynamic>> getProductionWeights(int id) async => {
    'lot': id,
    'lot_nom': 'Lot fictif',
    'effectif_actuel': 10,
    'pesees': [],
  };
  @override
  Future<dynamic> createEspece(String name) async {
    writes++;
    throw StateError('No mutation expected');
  }
}

void main() {
  testWidgets('classic purchase fields remain usable when tablet policy is disabled',(tester) async {
    final api=RoutingApi()..policy=false;
    await tester.pumpWidget(testApp(Scaffold(body:Builder(builder:(context)=>TextButton(
      onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>AddAchatScreen(apiService:api))),
      child:const Text('Ouvrir achat'))))));
    await tester.tap(find.text('Ouvrir achat'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1),'Pou');await tester.pumpAndSettle();
    await tester.tap(find.text('Poulet').last);await tester.pumpAndSettle();
    final fields=find.byType(TextFormField);
    for(final entry in {0:'Lot classique fictif',2:'10',3:'100'}.entries) {
      await tester.ensureVisible(fields.at(entry.key));await tester.enterText(fields.at(entry.key),entry.value);
    }
    tester.testTextInput.hide();await tester.pumpAndSettle();
    final submit=find.byType(ElevatedButton);await tester.ensureVisible(submit);await tester.pumpAndSettle();
    await tester.tap(submit);await tester.pumpAndSettle();
    expect(api.purchase,{'nom':'Lot classique fictif','quantite':10,'total':100.0,'unitaire':10.0});
    expect(api.writes,1);await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('classic weight fields remain usable when tablet policy is disabled',(tester) async {
    final api=RoutingApi()..policy=false;
    await tester.pumpWidget(testApp(GrowthTrackingScreen(apiService:api,lotId:1,lotName:'Lot fictif')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.add));await tester.tap(find.byIcon(Icons.add));await tester.pumpAndSettle();
    final fields=find.byType(TextFormField);
    await tester.enterText(fields.at(0),'2');await tester.enterText(fields.at(1),'3.000');
    await tester.tap(find.descendant(of:find.byType(AlertDialog),matching:find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(api.weight,{'lot':1,'nombre':2,'poids':3.0});expect(api.writes,1);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  test(
    'a signed-permission refusal has a comprehensible shared-screen explanation',
    () {
      expect(
        tabletErrorMessage(
          StateError('Profil verrouillé ou permission refusée.'),
        ),
        contains('le droit correspondant'),
      );
      expect(
        tabletErrorMessage(StateError('Unknown synthetic sensitive detail')),
        isNot(contains('sensitive detail')),
      );
    },
  );
  testWidgets(
    'weight entry retains consultation and routes device-policy writes',
    (tester) async {
      final api = RoutingApi();
      await tester.pumpWidget(
        testApp(
          GrowthTrackingScreen(
            apiService: api,
            lotId: 1,
            lotName: 'Lot fictif',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Demandez au propriétaire de préparer cet accès pour travailler sans Internet.',
        ),
        findsOneWidget,
      );
      expect(find.byType(Form), findsNothing);
      expect(api.writes, 0);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  for (final condition in ['legacy', 'owner', 'denied', 'offline']) {
    testWidgets(
      'entry gate $condition retains strict role and availability checks',
      (tester) async {
        final api = RoutingApi()..policy = false;
        if (condition == 'owner') {
          api.role = 'OWNER';
          api.rights = [];
        }
        if (condition == 'denied') api.rights = [];
        if (condition == 'offline') api.unavailable = true;
        var built = 0;
        await tester.pumpWidget(
          testApp(
            TerrainEntryGate(
              api: api,
              actions: const {'purchases.create'},
              builder: (_) {
                built++;
                return const Scaffold(body: Text('Classic permitted'));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(built, condition == 'legacy' ? 1 : 0);
        expect(
          find.text('Classic permitted'),
          condition == 'legacy' ? findsOneWidget : findsNothing,
        );
        if (condition == 'owner') {
          expect(
            find.textContaining('Le propriétaire consulte'),
            findsOneWidget,
          );
        }
        if (condition == 'denied') {
          expect(
            find.textContaining('Vous ne disposez pas du droit'),
            findsOneWidget,
          );
        }
        if (condition == 'offline') {
          expect(find.text('Réessayer'), findsOneWidget);
        }
        expect(api.writes, 0);
        await tester.pumpWidget(const SizedBox());
        api.close();
      },
    );
  }
  testWidgets(
    'expense entry clearly explains the shared online and offline tablet route',
    (tester) async {
      final api = RoutingApi()..rights = ['expenses.create'];
      await tester.pumpWidget(testApp(AddDepenseScreen(apiService: api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('sans Internet'), findsOneWidget);
      expect(find.text('Ouvrir l’espace éleveur'), findsOneWidget);
      expect(find.byType(Form), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
  for (final name in ['achat', 'mouvement', 'aliment']) {
    testWidgets(
      '$name redirects device-policy entry before initializing incompatible form',
      (tester) async {
        final api = RoutingApi();
        final Widget screen = switch (name) {
          'achat' => AddAchatScreen(apiService: api),
          'mouvement' => AddMouvementScreen(apiService: api),
          _ => FeedDistributionFormScreen(
            apiService: api,
            lotId: 1,
            lotName: 'Lot fictif',
          ),
        };
        await tester.pumpWidget(testApp(screen));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Demandez au propriétaire de préparer cet accès pour travailler sans Internet.',
          ),
          findsOneWidget,
        );
        expect(find.text('Ouvrir l’espace éleveur'), findsOneWidget);
        expect(find.byType(Form), findsNothing);
        expect(api.reads, 0);
        expect(api.writes, 0);
        await tester.pumpWidget(const SizedBox());
        api.close();
      },
    );
  }
}
