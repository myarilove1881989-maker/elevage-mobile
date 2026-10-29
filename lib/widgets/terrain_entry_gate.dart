import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/permission_contract.dart';
import '../screens/farmer_access_screen.dart';

/// Presentation routing only. Server permissions and signed grants remain authoritative.
class TerrainEntryGate extends StatefulWidget {
  const TerrainEntryGate({
    super.key,
    required this.api,
    required this.actions,
    required this.builder,
    this.ownerBuilder,
  });
  final ApiService api;
  final Set<String> actions;
  final WidgetBuilder builder;
  final WidgetBuilder? ownerBuilder;
  @override
  State<TerrainEntryGate> createState() => _TerrainEntryGateState();

  static Future<bool> allowClassic(
    BuildContext context,
    ApiService api,
    Set<String> actions,
  ) async {
    final token = ApiService.sessionIdentity;
    String? message;
    try {
      message = await _decision(api, actions);
    } catch (_) {
      message = _unavailable;
    }
    if (!context.mounted) return false;
    if (token != (ApiService.sessionIdentity)) message = _unavailable;
    if (message == null) return true;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => _notice(message!)),
    );
    return false;
  }
}

const _tablet =
    'Demandez au propriétaire de préparer cet accès pour travailler sans Internet.';
const _unavailable =
    'Impossible de vérifier votre accès. Reconnectez-vous ou contactez le propriétaire.';

Future<String?> _decision(ApiService api, Set<String> actions) async {
  return (await TerrainEntryAccess.read(api, actions)).message;
}

class TerrainEntryAccess {
  const TerrainEntryAccess(this.rights, this.tabletRequired, this.message);
  final PermissionContract rights;
  final bool tabletRequired;
  final String? message;
  static Future<TerrainEntryAccess> read(
    ApiService api,
    Set<String> actions,
  ) async {
    final caps = await api.get('/me/capabilities/');
    if (caps is! Map ||
        caps['user'] is! int ||
        caps['exploitation'] is! int ||
        caps['role'] is! String ||
        caps['membership'] is! Map ||
        caps['membership']['version'] is! int ||
        caps['permission_contract'] is! Map<String, dynamic> ||
        caps['offline_policy_enabled'] is! bool) {
      throw StateError('Invalid capabilities');
    }
    final rights = PermissionContract.decode(
      caps['permission_contract'] as Map<String, dynamic>,
      userId: caps['user'] as int,
      farmId: caps['exploitation'] as int,
      role: caps['role'] as String,
      rightsVersion: caps['membership']['version'] as int,
    );
    final required = caps['offline_policy_enabled'] == true && !api.hasUnifiedOfflineSession;
    final message = rights.role == 'OWNER'
        ? 'Le propriétaire consulte et supervise les opérations. La saisie terrain est réservée aux employés autorisés.'
        : !actions.any(rights.allows)
        ? 'Vous ne disposez pas du droit nécessaire pour cette saisie. Contactez le propriétaire.'
        : required
        ? _tablet
        : null;
    return TerrainEntryAccess(rights, required, message);
  }
}

Widget _notice(String message) => Scaffold(
  appBar: AppBar(title: const Text('Saisie des opérations')),
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        if (message == _tablet || message == _unavailable) ...[
          const SizedBox(height: 16),
          const Text(
            'Connectez-vous avec votre identifiant et votre code personnel.',
          ),
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const FarmerAccessScreen()),
              ),
              child: const Text('Ouvrir l’espace éleveur'),
            ),
          ),
        ],
      ],
    ),
  ),
);

class _TerrainEntryGateState extends State<TerrainEntryGate> {
  late Future<TerrainEntryAccess> decision;
  late String? token;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    token = ApiService.sessionIdentity;
    decision = TerrainEntryAccess.read(widget.api, widget.actions);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TerrainEntryAccess>(
    future: decision,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (token != (ApiService.sessionIdentity)) {
        return _notice(_unavailable);
      }
      if (snapshot.hasError) {
        return Scaffold(appBar: AppBar(title: const Text('Accès aux opérations')),
          body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            const Text('Accès indisponible. Reconnectez-vous ou réessayez plus tard.'),
            TextButton(onPressed: () => setState(_load), child: const Text('Réessayer')),
            TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const FarmerAccessScreen())),child:const Text('Ouvrir l’espace éleveur')),
          ])));
      }
      final access = snapshot.data!;
      if (access.rights.role == 'OWNER' && widget.ownerBuilder != null) {
        return widget.ownerBuilder!(context);
      }
      return access.message == null ? widget.builder(context) : _notice(access.message!);
    },
  );
}

/// Hides a business command until this identity's server rights are verified.
/// Does not replace the fresh action-time checks or signed offline grants.
class BusinessCommand extends StatefulWidget {
  const BusinessCommand({super.key, required this.api, required this.actions, required this.child});
  final ApiService api;
  final Set<String> actions;
  final Widget child;
  @override
  State<BusinessCommand> createState() => _BusinessCommandState();
}
class _BusinessCommandState extends State<BusinessCommand> {
  late Future<TerrainEntryAccess> access;
  String? identity;
  void load() {
    identity = ApiService.sessionIdentity;
    access = TerrainEntryAccess.read(widget.api, widget.actions);
  }
  @override
  void initState() { super.initState(); load(); }
  @override
  void didUpdateWidget(BusinessCommand old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api || identity != (ApiService.sessionIdentity) ||
        !setEquals(old.actions, widget.actions)) load();
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<TerrainEntryAccess>(
    future: access, builder: (context, snapshot) {
      final rights = snapshot.data?.rights;
      if (snapshot.connectionState != ConnectionState.done || snapshot.hasError ||
          identity != (ApiService.sessionIdentity) || rights?.role != 'OPERATEUR' ||
          !widget.actions.any(rights!.allows)) return const SizedBox.shrink();
      return widget.child;
    });
}
