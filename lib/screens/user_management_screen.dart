import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/user_administration_service.dart';
import '../services/permission_contract.dart';

const permissionGroups = {
  'purchases': 'Achats',
  'animal_sales': 'Ventes animaux',
  'expenses': 'Dépenses',
  'mortality': 'Mortalités',
  'births': 'Naissances',
  'donations': 'Dons',
  'thefts': 'Vols',
  'clients': 'Clients',
  'species': 'Espèces',
  'egg_collections': 'Collectes d’œufs',
  'egg_sales': 'Ventes d’œufs',
  'cash': 'Encaissements',
  'feed': 'Alimentation',
  'weights': 'Pesées',
  'agenda': 'Agenda',
};
const permissionActions = {
  'create': 'Créer',
  'update': 'Modifier',
  'delete': 'Supprimer',
  'cancel': 'Annuler — original conservé',
  'read': 'Consulter',
  'plan': 'Planifier, assigner et annuler',
  'progress': 'Progresser et rendre compte',
};

class PermissionEditor extends StatelessWidget {
  const PermissionEditor({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final Set<String> selected;
  final void Function(String, bool) onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Tous les employés actifs peuvent consulter les données et finances de leur exploitation. Ces lectures communes ne sont pas révocables individuellement.',
      ),
      for (final group in permissionGroups.entries)
        ExpansionTile(
          title: Text(group.value),
          children: [
            for (final action in PermissionContract.domains[group.key]!)
              if (action != 'read' || group.key == 'agenda')
                CheckboxListTile(
                  key: ValueKey('permission:${group.key}.$action'),
                  title: Text(permissionActions[action]!),
                  value: selected.contains('${group.key}.$action'),
                  onChanged: (value) =>
                      onChanged('${group.key}.$action', value ?? false),
                ),
          ],
        ),
      const Text(
        'Les droits fins de rapprochement restent préparés et ne sont pas activés dans cette rubrique.',
      ),
    ],
  );
}

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key, this.service});
  final UserAdministrationService? service;
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.reset});
  final bool reset;
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final name = TextEditingController(),
      username = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  final selected = <String>{};
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    password.clear();
    password.dispose();
    name.dispose();
    username.dispose();
    email.dispose();
    super.dispose();
  }

  void submit() {
    if (!form.currentState!.validate()) {
      return;
    }
    final data = <String, dynamic>{
      if (!widget.reset) 'display_name': name.text.trim(),
      if (!widget.reset) 'username': username.text.trim(),
      if (!widget.reset) 'email': email.text.trim(),
      if (!widget.reset) 'permissions': selected.toList()..sort(),
      (widget.reset ? 'new_password' : 'password'): password.text,
    };
    password.clear();
    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reset ? 'Réinitialiser le mot de passe' : 'Ajouter un utilisateur',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.reset) ...[
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom affiché'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Indiquez un nom.' : null,
                ),
                TextFormField(
                  controller: username,
                  decoration: const InputDecoration(
                    labelText: 'Identifiant unique',
                  ),
                  validator: (v) =>
                      v == null || !RegExp(r'^[\w.@+-]+$').hasMatch(v.trim())
                      ? 'Indiquez un identifiant sans espace.'
                      : null,
                ),
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(
                    labelText: 'Email facultatif',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
              TextFormField(
                controller: password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe initial (4 caractères minimum)',
                ),
                validator: (v) => v == null || v.trim().length < 4
                    ? 'Utilisez au moins 4 caractères.'
                    : null,
              ),
              TextButton(
                onPressed: () => setState(
                  () => password.text =
                      UserAdministrationService.generatePassword(),
                ),
                child: const Text('Générer un code de 4 chiffres'),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Transmission personnelle'),
                    content: SelectableText(password.text),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fermer'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Voir pour transmettre personnellement'),
              ),
              const Text(
                'Transmettez ce mot de passe personnellement pendant cette étape. Il ne sera plus consultable après fermeture. L’employé devra le remplacer. Son PIN reste inchangé.',
              ),
              if (!widget.reset)
                PermissionEditor(
                  selected: selected,
                  onChanged: (code, value) => setState(() {
                    if (value) {
                      selected.add(code);
                    } else {
                      selected.remove(code);
                    }
                  }),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: submit, child: const Text('Continuer')),
    ],
  );
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late final service =
      widget.service ?? UserAdministrationService(ApiService());
  List<Map<String, dynamic>> rows = [];
  bool loading = true, ready = false;
  String? error;
  String? displayedSession;
  bool get canEdit =>
      ready &&
      !loading &&
      displayedSession == (ApiService.sessionIdentity);
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    if (widget.service == null) {
      service.api.close();
    }
    super.dispose();
  }

  Future<void> load() async {
    final session = ApiService.sessionIdentity;
    setState(() {
      loading = true;
      ready = false;
      error = null;
      if (displayedSession != session) {
        rows = [];
      }
    });
    try {
      await service.initialize();
      final result = await service.list();
      if (mounted) {
        setState(() {
          rows = result;
          ready = true;
          displayedSession = session;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Gestion indisponible. Une connexion propriétaire au serveur compatible est nécessaire. Réessayez sans changer d’écran.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<bool> confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmer la modification'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> mutate(Future<Map<String, dynamic>> Function() action) async {
    setState(() {
      loading = true;
      ready = false;
      error = null;
    });
    try {
      final result = await action();
      if (!mounted) {
        return;
      }
      setState(() {
        final index = rows.indexWhere((row) => row['id'] == result['id']);
        if (index < 0) {
          rows.add(result);
        } else {
          rows[index] = result;
        }
        ready = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modification confirmée par le serveur.')),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Modification non confirmée. Actualisez la liste avant de réessayer ; les droits affichés n’ont pas été modifiés localement.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> edit(Map<String, dynamic> member) async {
    final selected = Set<String>.from(member['permissions'] as List);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Droits de ${member['username']}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: PermissionEditor(
                selected: selected,
                onChanged: (code, value) => update(() {
                  if (value) {
                    selected.add(code);
                  } else {
                    selected.remove(code);
                  }
                }),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vérifier et appliquer'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true &&
        mounted &&
        await confirm(
          'Les grants concernés seront révoqués. Les déclarations déjà enregistrées sont conservées. Le serveur confirme les nouveaux droits après enregistrement.',
        )) {
      await mutate(
        () =>
            service.update(member, {'permissions': selected.toList()..sort()}),
      );
    }
  }

  Future<void> accountForm({Map<String, dynamic>? member}) async {
    Map<String, dynamic>? data;
    try {
      data = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _AccountDialog(reset: member != null),
      );
      if (data == null || !mounted) {
        return;
      }
      if (member != null &&
          !await confirm(
            'Les sessions et grants de cet utilisateur seront révoqués. Il devra changer ce mot de passe après authentification. Les déclarations et le PIN sont conservés.',
          )) {
        return;
      }
      final payload = data;
      await mutate(
        () => member == null
            ? service.create(payload)
            : service.reset(member, payload['new_password'] as String),
      );
    } finally {
      data?.remove('password');
      data?.remove('new_password');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Gestion des utilisateurs'),
      actions: [
        IconButton(
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualiser',
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Administration en ligne • réservée au propriétaire'),
            const Text(
              'Le propriétaire consulte et administre. Pour saisir des opérations, utilisez un compte terrain distinct.',
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error!, key: const ValueKey('adminError')),
              ),
            FilledButton.icon(
              onPressed: canEdit ? () => accountForm() : null,
              icon: const Icon(Icons.person_add),
              label: const Text('Ajouter un utilisateur'),
            ),
            for (final member in rows.where(
              (row) =>
                  row['role'] == 'OPERATEUR' &&
                  displayedSession == (ApiService.sessionIdentity),
            ))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${member['display_name'] ?? ''} • ${member['username']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${member['is_active'] == true ? 'Actif' : 'Inactif'} • ${(member['permissions'] as List).length} ${(member['permissions'] as List).length == 1 ? 'droit attribué' : 'droits attribués'}',
                      ),
                      if (member['password_change_required'] == true)
                        const Text('Changement de mot de passe requis'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: canEdit ? () => edit(member) : null,
                            child: const Text('Modifier les droits'),
                          ),
                          TextButton(
                            onPressed: canEdit
                                ? () async {
                                    if (await confirm(
                                      member['is_active'] == true
                                          ? 'Désactiver cet utilisateur et révoquer ses sessions et grants ? Ses déclarations sont conservées.'
                                          : 'Réactiver cet utilisateur ? Ses anciens grants restent révoqués.',
                                    )) {
                                      await mutate(
                                        () => service.update(member, {
                                          'is_active':
                                              member['is_active'] != true,
                                        }),
                                      );
                                    }
                                  }
                                : null,
                            child: Text(
                              member['is_active'] == true
                                  ? 'Désactiver'
                                  : 'Réactiver',
                            ),
                          ),
                          TextButton(
                            onPressed: canEdit
                                ? () => accountForm(member: member)
                                : null,
                            child: const Text('Réinitialiser le mot de passe'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
