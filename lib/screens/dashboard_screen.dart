import 'package:app_elevage/services/api_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/financial_indicators.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_elevage/screens/add_achat_screen.dart';
import 'package:app_elevage/screens/add_mouvement_screen.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/screens/lot_list_screen.dart';
import 'package:app_elevage/screens/production_tracking_screen.dart';

import '../main.dart';
import '../config.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/farm_navigation.dart';
import '../widgets/cancellation_dialog.dart';
import '../services/farm_session.dart';
import '../services/farmer_runtime.dart';
import '../services/server_connection.dart';
import '../services/permission_contract.dart';
import '../services/user_administration_service.dart';
import '../offline/sync_state.dart';
import 'operation_history_screen.dart';

import 'owner_operation_history_screen.dart';
import 'user_management_screen.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:app_elevage/screens/stock_detail_screen.dart';
import 'package:app_elevage/screens/ca_detail_screen.dart';
import 'package:app_elevage/screens/depense_detail_screen.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:app_elevage/screens/client_list_screen.dart';
import 'package:app_elevage/screens/dettes_screen.dart';
import 'package:app_elevage/screens/performance_screen.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/screens/settings_screen.dart';
import 'package:app_elevage/l10n/app_localizations.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

class _DashboardReadFailure implements Exception {
  const _DashboardReadFailure(this.label,this.connectionFailed);
  final String label;
  final bool connectionFailed;
}

class DashboardScreen extends StatefulWidget {
  final ApiService apiService;

  const DashboardScreen({super.key, required this.apiService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late ApiService apiService;
  String _receiptState='';
  Timer? _receiptTimer;
  String get _confirmedReceipts=>apiService.localOperations.where((r)=>r.businessStatus=='CONFIRMED')
      .map((r)=>r.operationId).join('|');
  void _receiptsChanged() {
    final next=_confirmedReceipts;
    if(next==_receiptState) return;
    _receiptState=next;
    _receiptTimer?.cancel();
    _receiptTimer=Timer(const Duration(milliseconds:400),() {if(mounted) _reload();});
  }
  Widget _expenseScreen()=>apiService is FarmerApiService && apiService.hasUnifiedOfflineSession
    ?AddDepenseScreen(tablet:(apiService as FarmerApiService).runtime.tablet,simple:true)
    :AddDepenseScreen(apiService:apiService);
  late final ServerConnection serverConnection;
  Widget _connectionIndicator()=>AnimatedBuilder(animation:Listenable.merge([
    serverConnection,if(apiService is FarmerApiService) (apiService as FarmerApiService).runtime.tablet]),
    builder:(context,_) {
      final tablet=apiService is FarmerApiService?(apiService as FarmerApiService).runtime.tablet:null;
      return ConnectionIndicator(networkAvailable:tablet?.sync?.networkAvailable,lastSuccess:serverConnection.lastSuccess,
        serverUnavailable:serverConnection.available==false,syncing:tablet?.sync?.busy??false,
        pending:tablet?.sync?.summary.pending,conflicts:tablet?.sync?.summary.conflicts,onSummary:_openHistory);
    });
  FarmSession? commonSession;
  String? commonSessionToken;

  Future<void> _loadCommonSession() async {
    final token=(ApiService.sessionIdentity);
    if(token==null) return;
    try {
      final result=await apiService.get('/me/capabilities/');
      final rights=PermissionContract.decode(Map<String,dynamic>.from(result['permission_contract'] as Map),
        userId:result['user'] as int,farmId:result['exploitation'] as int,
        role:result['role'] as String,rightsVersion:result['membership']['version'] as int);
      if(!mounted || token!=(ApiService.sessionIdentity)) return;
      setState(() {commonSessionToken=token;commonSession=FarmSession(userId:rights.userId,farmId:rights.farmId,
        role:rights.role,permissions:rights,origin:apiService.hasUnifiedOfflineSession?SessionOrigin.tabletProfile:SessionOrigin.personalHttp,
        network:NetworkState.available,sync:const SyncSummary());});
    } catch(_) { if(mounted) setState(()=>commonSession=null); }
  }

  Future<bool> _cancelTask(Map<String,dynamic> task) async {
    await _loadCommonSession();
    if(!mounted || commonSessionToken!=(ApiService.sessionIdentity) || commonSession?.canCancelTask!=true) return false;
    final reason=await confirmCancellation(context,'Annuler cette tâche ?');
    if(reason==null || !mounted || commonSessionToken!=(ApiService.sessionIdentity)) return false;
    try {
      await apiService.cancelTask(task['id'] as int,version:task['version'] as int,reason:reason);
      if(!mounted || commonSessionToken!=(ApiService.sessionIdentity)) return false;
      return true;
    } catch(_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Annulation non confirmée. Actualisez l’agenda avant de réessayer.')));
      return false;
    }
  }

  Widget? _taskCancellationButton(Map<String,dynamic> task) {
    if(commonSession?.canCancelTask!=true || commonSessionToken!=(ApiService.sessionIdentity)) return null;
    return IconButton(tooltip:'Annuler la tâche',icon:const Icon(Icons.cancel_outlined),onPressed:() async {
      if(await _cancelTask(task)) await loadTasks();
    });
  }

  Map<String, dynamic>? data;
  List lots = [];
  List especes = [];

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  List _createdSpecies(List allSpecies, List currentLots) {
    final createdIds = currentLots
        .map((lot) => _intValue(lot['espece']))
        .whereType<int>()
        .toSet();

    return allSpecies
        .where((species) => createdIds.contains(_intValue(species['id'])))
        .toList();
  }

  int? selectedLotId;
  int? selectedEspeceId;

  final ScrollController _tasksScrollController = ScrollController();

  bool isLoading = true;

  double? totalDettes;
  String? loadError;
  DateTime? lastApiSuccess;
  bool serverUnavailable = false;
  int? displayedLotId, displayedEspeceId;
  String username = '';
  String farmName = '';
  Future<void> loadFarmName() async {
    final identity = ApiService.sessionIdentity;
    try {
      final profile = await apiService.get('/farm-profile/');
      if (mounted && identity == ApiService.sessionIdentity) {
        setState(() => farmName = profile['nom']?.toString().trim() ?? '');
      }
    } catch (_) { /* Keep the last confirmed name during a connection failure. */ }
  }

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<String, List<Map<String, dynamic>>> events = {};

  String getDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> loadUsername() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      username = prefs.getString("username") ?? '';
    });
  }

  void _openHistory() {
    final owner = commonSessionToken == (ApiService.sessionIdentity) &&
        commonSession?.role == 'OWNER';
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => owner
        ? OwnerOperationHistoryScreen(api: apiService)
        : OperationHistoryScreen(api: apiService)));
  }

  Future<void> _logout() async {
    await apiService.logout();

    if (!mounted || apiService is FarmerApiService) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(apiService: apiService)),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    apiService = widget.apiService;
    _receiptState=_confirmedReceipts;
    apiService.sessionChanges?.addListener(_receiptsChanged);
    serverConnection=apiService is FarmerApiService?(apiService as FarmerApiService).runtime.connection
      :ServerConnection(baseUrl:ApiService.baseUrl,check:apiService.probeServer);
    if(apiService is! FarmerApiService) serverConnection.start();
    _loadCommonSession();
    loadUsername();
    initData();
  }

  Future<void> loadTasks() async {
    final res = await apiService.getTasks();

    Map<String, List<Map<String, dynamic>>> temp = {};

    for (var task in res) {
      final rawDate = task["date"];
      final date = rawDate.split("T")[0];

      temp.putIfAbsent(date, () => []);
      temp[date]!.add(task); // ?? garde tout (id + title)
    }

    if (!mounted) { return; }
    setState(() {
      events = temp;
    });
  }

  Map<String, List<Map<String, dynamic>>> _taskEvents(List rawTasks) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final task in rawTasks) {
      final date = task['date'].split('T')[0] as String;
      result.putIfAbsent(date, () => []).add(Map<String, dynamic>.from(task));
    }
    return result;
  }

  Future<T> _requiredRead<T>(String label,Future<T> work) async {
    try {return await work;} catch(error) {
      throw _DashboardReadFailure(label,error is ApiConnectionException);
    }
  }
  void _loadFailed(Object error) {
    loadError = data == null
        ? error is _DashboardReadFailure
            ? 'Chargement incomplet : ${error.label}. Reconnectez-vous avec Internet pour préparer ces données.'
            : 'Données indisponibles. Réessayez lorsque la connexion le permet.'
        : 'Actualisation impossible. Les dernières données affichées sont conservées.';
    serverUnavailable = error is ApiConnectionException ||
      (error is _DashboardReadFailure && error.connectionFailed);
    lastApiSuccess = null;
    // Keep the filter consistent with the retained snapshot after a failed read.
    selectedLotId = displayedLotId;
    selectedEspeceId = displayedEspeceId;
  }

  Future<void> initData() async { await _reload(includeTasks: true); }

  Future<bool> _reload({bool includeTasks = false}) async {
    unawaited(loadFarmName());
    final lotId = selectedLotId;
    final speciesId = selectedEspeceId;
    if (mounted) { setState(() { isLoading = true; loadError = null; }); }
    try {
      final results = await Future.wait<Object>([
        _requiredRead('bilan du tableau de bord',lotId == null ? apiService.getDashboard(especeId: speciesId)
            : apiService.getLotDetail(lotId)),
        _requiredRead('liste des lots',apiService.getLots()),
        _requiredRead('liste des espèces',apiService.getEspeces()),
        _requiredRead('total des dettes',apiService.getTotalDettes()),
        if (includeTasks) _requiredRead('liste des tâches',apiService.getTasks()),
      ]);
      final nextData = Map<String, dynamic>.from(results[0] as Map);
      final nextLots = results[1] as List;
      final nextSpecies = _createdSpecies(results[2] as List, nextLots);
      if ((speciesId != null && !nextSpecies.any((item) => _intValue(item['id']) == speciesId)) ||
          (lotId != null && !nextLots.any((item) => _intValue(item['id']) == lotId))) {
        throw StateError('Le périmètre affiché ne figure plus dans les données reçues.');
      }
      final nextDebt = results[3] as double;
      final nextEvents = includeTasks ? _taskEvents(results[4] as List) : events;
      if (!mounted) { return false; }
      // Commit the view snapshot only when every requested read succeeded.
      setState(() {
        data = nextData; lots = nextLots; especes = nextSpecies;
        totalDettes = nextDebt; events = nextEvents;
        displayedLotId = lotId; displayedEspeceId = speciesId;
        lastApiSuccess = DateTime.now(); serverUnavailable = false;
      });
      return true;
    } catch (error) {
      if (mounted) { setState(() => _loadFailed(error)); }
      return false;
    } finally {
      if (mounted) { setState(() => isLoading = false); }
    }
  }

  Future<void> _loadScope({int? lotId, int? speciesId}) async {
    if (mounted) { setState(() { isLoading = true; loadError = null; }); }
    try {
      final result = lotId == null ? await apiService.getDashboard(especeId: speciesId)
          : await apiService.getLotDetail(lotId);
      if (!mounted) { return; }
      setState(() {
        data = result; displayedLotId = lotId; displayedEspeceId = speciesId;
        lastApiSuccess = DateTime.now(); serverUnavailable = false;
      });
    } catch (error) {
      if (mounted) { setState(() => _loadFailed(error)); }
    } finally {
      if (mounted) { setState(() => isLoading = false); }
    }
  }

  Future<void> fetchDashboard() => _loadScope();
  Future<void> fetchDashboardByEspece(int? especeId) => _loadScope(speciesId: especeId);
  Future<void> fetchLotDetail(int lotId) => _loadScope(lotId: lotId, speciesId: selectedEspeceId);

  Future<void> scheduleNotification(String title, DateTime date) async {
    final scheduledDate = tz.TZDateTime.from(
      DateTime(date.year, date.month, date.day, 8),
      tz.local,
    );

    await notificationsPlugin.zonedSchedule(
      0,
      "Tâche du jour",
      title,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'tasks',
          'Tasks',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Widget buildCard(
    String title,
    dynamic value,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    bool isMoney = false,
    String? unit,
  }) {
    final subtitle = value == null ? '' :
        unit ?? (isMoney ? AppSettings.instance.currency.symbol : '');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE4E8EC), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 34, color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value == null ? 'Indisponible' : isMoney
                          ? AppSettings.instance
                                .formatMoney(value)
                                .replaceAll(
                                  AppSettings.instance.currency.symbol,
                                  '',
                                )
                                .trim()
                          : value.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF607080),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Trait coloré en bas de la card
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List getFilteredLots() {
    if (selectedEspeceId == null) return lots;

    return lots.where((lot) {
      return _intValue(lot["espece"]) == selectedEspeceId;
    }).toList();
  }

  List<Map<String, dynamic>> _getTasksForDay() {
    final day = _selectedDay ?? DateTime.now();
    final key = getDateKey(day);

    return events[key] ?? [];
  }

  Future<void> refreshDashboard() async { await _reload(); }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("choisis d'abord une espèce ou lot")),
    );
  }

  void _showTasksForDay(DateTime day) {
    final key = getDateKey(day);
    final tasks = events[key] ?? [];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${context.tr('today_tasks')} ${day.day}/${day.month}"),
        content: tasks.isEmpty
            ? Text(context.tr('no_task'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: tasks
                    .map(
                      (t) => ListTile(
                        leading: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        title: Text(t["title"]),

                        // ?? BOUTON SUPPRIMER
                        trailing: _taskCancellationButton(t),
                      ),
                    )
                    .toList(),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('close')),
          ),
        ],
      ),
    );
  }

  bool get _mayPlanTasks => commonSessionToken == (ApiService.sessionIdentity) &&
      commonSession?.role == 'OWNER' && commonSession?.permissions?.allows('agenda.plan') == true;

  void _showAgenda() {
    showModalBottomSheet<void>(context:context,builder:(sheet)=>SafeArea(child:Column(
      mainAxisSize:MainAxisSize.min,children:[
        const ListTile(title:Text('Agenda')),
        ListTile(leading:const Icon(Icons.event),title:const Text('Voir les tâches du jour'),
          onTap:(){Navigator.pop(sheet);_showTasksForDay(_selectedDay??_focusedDay);}),
        if(_mayPlanTasks) ListTile(leading:const Icon(Icons.add_task),title:const Text('Attribuer une tâche'),
          onTap:(){Navigator.pop(sheet);_addTask();}),
      ])));
  }

  void _addTask() async {
    await _loadCommonSession();
    if(!mounted || !_mayPlanTasks) return;
    final captured=ApiService.sessionIdentity;
    List<Map<String,dynamic>> operators;
    try {
      final raw=await apiService.get('/memberships/');
      if(!mounted || captured!=ApiService.sessionIdentity || !_mayPlanTasks) return;
      operators=(raw as List).map((r)=>Map<String,dynamic>.from(r as Map))
        .where((r)=>r['role']=='OPERATEUR' && r['is_active']==true && r['exploitation']==commonSession!.farmId).toList();
    } catch (_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Impossible de charger les opérateurs. Reconnectez-vous pour attribuer une tâche.')));
      return;
    }
    if(!mounted) return;
    final title=TextEditingController();
    var day=_selectedDay??DateTime.now(); int? assignee; bool busy=false; String? error;
    final route=DialogRoute<bool>(context:context,builder:(dialog)=>StatefulBuilder(builder:(dialog,change)=>AlertDialog(
      title:Text(context.tr('new_task')),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(key:const Key('agendaTaskTitle'),controller:title,decoration:const InputDecoration(labelText:'Tâche')),
        DropdownButtonFormField<int>(key:const Key('agendaAssignee'),decoration:const InputDecoration(labelText:'Opérateur'),
          items:operators.map((r)=>DropdownMenuItem<int>(value:r['user'] as int,child:Text(r['username'].toString()))).toList(),
          onChanged:busy?null:(v)=>change(()=>assignee=v)),
        TextButton(onPressed:busy?null:() async {
          final selected=await showDatePicker(context:dialog,initialDate:day,firstDate:DateTime(2020),lastDate:DateTime(2100));
          if(selected!=null && dialog.mounted) change(()=>day=selected);
        },child:Text(MaterialLocalizations.of(dialog).formatMediumDate(day))),
        if(error!=null) Text(error!),
      ])),
      actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(dialog,false),child:Text(context.tr('cancel'))),
        FilledButton(onPressed:busy?null:() async {
          if(title.text.trim().isEmpty || assignee==null) {change(()=>error='Renseignez la tâche et son opérateur.');return;}
          change((){busy=true;error=null;});
          try {
            await _loadCommonSession();
            if(captured!=ApiService.sessionIdentity || !_mayPlanTasks) throw StateError('Session modifiée');
            await apiService.createTask(title.text.trim(),day,assignedTo:assignee);
            if(dialog.mounted) Navigator.pop(dialog,true);
          } catch (_) {if(dialog.mounted) change((){busy=false;error='Enregistrement non confirmé. Vérifiez l’agenda avant de recommencer.';});}
        },child:Text(context.tr('add')))])));
    final saved=await Navigator.of(context).push(route);await route.completed;title.dispose();
    if(saved==true && mounted) await loadTasks();
  }

  Future<void> _refreshAll() async {
    if (isLoading) { return; }
    final succeeded = await _reload(includeTasks: true);
    if (!mounted || !succeeded) { return; }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('data_updated'))));
  }

  Future<void> _openLots() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LotListScreen(apiService: apiService)),
    );
    if (result == true) await refreshDashboard();
  }

  Future<void> _openDepense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _expenseScreen(),
      ),
    );
    if (result == true) await refreshDashboard();
  }

  Future<void> _openProductionTracking() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductionTrackingScreen(apiService: apiService),
      ),
    );
  }

  Future<void> _openMouvement() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMouvementScreen(apiService: apiService),
      ),
    );
    if (result == true) await refreshDashboard();
  }

  Future<void> _openAchat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddAchatScreen(apiService: apiService)),
    );
    if (result == true) await refreshDashboard();
  }

  void _openClients() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientListScreen(apiService: apiService),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsScreen(apiService: apiService)),
    );
    if (mounted) await loadFarmName();
  }

  Future<void> _openTutorial(String languageCode) async {
    if (!Config.current.externalLinksAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Les liens externes sont désactivés dans le pilote.'),
        ));
      }
      return;
    }
    final fileName = languageCode == 'en'
        ? 'elevage-user-guide-en.pdf'
        : 'guide-utilisateur-elevage.pdf';
    final tutorialUrl = Uri.parse(
      'https://elevage-mobile.onrender.com/$fileName',
    );

    final opened = await launchUrl(
      tutorialUrl,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tutorial_open_error'))),
      );
    }
  }

  Future<void> _chooseTutorialLanguage() async {
    final languageCode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  context.tr('choose_tutorial_language'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF063B63),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(child: Text('FR')),
                title: Text(context.tr('tutorial_french')),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => Navigator.pop(sheetContext, 'fr'),
              ),
              ListTile(
                leading: const CircleAvatar(child: Text('EN')),
                title: Text(context.tr('tutorial_english')),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => Navigator.pop(sheetContext, 'en'),
              ),
            ],
          ),
        ),
      ),
    );

    if (languageCode != null && mounted) {
      await _openTutorial(languageCode);
    }
  }

  Widget _brandTitle() {
    return RichText(
      text: const TextSpan(
        style:TextStyle(fontFamily:'Roboto'),
        children: [
          TextSpan(
            text: "Elev'",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          TextSpan(
            text: "Age",
            style: TextStyle(
              color: Color(0xFF4CAF50),
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardHeading(double height) {
    // A fixed heading prevents scrolling content underneath the toolbar from
    // cutting the title. Compact viewports (including the keyboard) need less height.
    if (height < 70) { return const SizedBox.shrink(); }
    final compact = height < 350;
    return Padding(
                padding: EdgeInsets.fromLTRB(8, compact ? 8 : 28, 8, compact ? 8 : 22),
                child: Column(
                  children: [
                    RichText(
                      key: const Key('dashboardHeading'),
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: compact ? 2 : null,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style:const TextStyle(fontFamily:'Roboto'),
                        children: [
                          TextSpan(
                            text: context.tr('dashboard'),
                            style: TextStyle(
                              color: Color(0xFF063B63),
                              fontSize: compact ? 28 : 42,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (farmName.isNotEmpty)
                            TextSpan(
                              text: " $farmName",
                              style: TextStyle(
                                color: Color(0xFF16834B),
                                fontSize: compact ? 28 : 42,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (height >= 160) Text(
                      context.tr('overview'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF607080),
                        fontSize: compact ? 16 : 22,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              );
  }

  Widget _navigationDrawer() {
    Widget item(String label, IconData icon, VoidCallback action) {
      return ListTile(
        leading: Icon(icon, color: const Color(0xFF063B63)),
        title: Text(label),
        onTap: () {
          Navigator.pop(context);
          action();
        },
      );
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFF063B63),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: _brandTitle(),
            ),
            FarmNavigation(session:commonSessionToken==(ApiService.sessionIdentity)?commonSession:null,labels:{
              FarmDestination.dashboard:context.tr('dashboard'),
              FarmDestination.lots:AppLocalizations.of(context).languageCode=='en'?'Batches':'Lots',
              FarmDestination.purchases:context.tr('purchases'),
              FarmDestination.sales:context.tr('sale'),
              FarmDestination.expenses:context.tr('expenses'),
              FarmDestination.movements:context.tr('movements'),
              FarmDestination.history:context.tr('history'),
              FarmDestination.agenda:AppLocalizations.of(context).languageCode=='en'?'Tasks':'Agenda',
              FarmDestination.production:context.tr('production_tracking'),
              FarmDestination.settings:context.tr('settings'),
              FarmDestination.users:AppLocalizations.of(context).languageCode=='en'?'User management':'Gestion des utilisateurs',
            },actions:{
              FarmDestination.dashboard:()=>Navigator.pop(context),
              FarmDestination.lots:() {Navigator.pop(context);_openLots();},
              FarmDestination.purchases:() {Navigator.pop(context);_openAchat();},
              FarmDestination.sales:() {Navigator.pop(context);_openMouvement();},
              FarmDestination.expenses:() {Navigator.pop(context);_openDepense();},
              FarmDestination.movements:() {Navigator.pop(context);_openMouvement();},
              FarmDestination.history:() {Navigator.pop(context);_openHistory();},
              FarmDestination.agenda:() {Navigator.pop(context);_showAgenda();},
              FarmDestination.production:() {Navigator.pop(context);_openProductionTracking();},
              FarmDestination.settings:() {Navigator.pop(context);_openSettings();},
              FarmDestination.users:() {Navigator.pop(context);Navigator.push(context,MaterialPageRoute(builder:(_)=>UserManagementScreen(service:UserAdministrationService(apiService))));},
            }),
            item(
              context.tr('tutorial'),
              Icons.menu_book_outlined,
              _chooseTutorialLanguage,
            ),
            const Divider(height: 1),
            item(context.tr('logout'), Icons.logout, _logout),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _receiptTimer?.cancel();apiService.sessionChanges?.removeListener(_receiptsChanged);
    if(apiService is! FarmerApiService) serverConnection.dispose();
    _tasksScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kpis = data?["kpis"] ?? {};
    final filteredLots = getFilteredLots();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showNavActions = screenWidth >= 1100 && MediaQuery.textScalerOf(context).scale(13) <= 16;
    final navSpacing = screenWidth < 1200 ? 4.0 : 18.0;

    return Scaffold(
      drawer: _navigationDrawer(),
      appBar: screenWidth < 700
          ? AppBar(
              backgroundColor: const Color(0xFF063B63),
              foregroundColor: Colors.white,
              toolbarHeight: 64,
              leading: Builder(
                builder: (menuContext) => IconButton(
                  tooltip: context.tr('open_menu'),
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(menuContext).openDrawer(),
                ),
              ),
              title: const Text('Élev’Age'),
              actions: [
                _connectionIndicator(),
                IconButton(
                  tooltip: context.tr('refresh'),
                  onPressed: isLoading ? null : _refreshAll,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: const Color(0xFF063B63),
              foregroundColor: Colors.white,
              elevation: 0,
              toolbarHeight: 76,
              title: Row(
                children: [
                  // =========================
                  // LOGO ELEV'AGE
                  // =========================
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (menuContext) => IconButton(
                          tooltip: context.tr('open_menu'),
                          icon: const Icon(Icons.menu, size: 30),
                          onPressed: () =>
                              Scaffold.of(menuContext).openDrawer(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      RichText(
                        text: const TextSpan(
                          style:TextStyle(fontFamily:'Roboto'),
                          children: [
                            TextSpan(
                              text: "Elev'",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                              ),
                            ),
                            TextSpan(
                              text: "Age",
                              style: TextStyle(
                                color: Color(0xFF4CAF50),
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Espace entre le logo et les boutons
                  const SizedBox(width: 8),

                  // =========================
                  // NAVIGATION
                  // =========================
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _connectionIndicator(),
                        // ACTUALISER
                        InkWell(
                          onTap: isLoading ? null : _refreshAll,
                          child: SizedBox(
                            width: screenWidth < 700 ? 44 : 76,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.refresh,
                                  color: Colors.white,
                                  size: 27,
                                ),
                                if (screenWidth >= 700) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    context.tr('refresh'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        if (showNavActions) ...[
                          const SizedBox(width: 8),

                          // ACHATS
                          InkWell(
                            onTap: _openAchat,
                            child: SizedBox(
                              width: 80,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shopping_bag_outlined,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    context.tr('purchases'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(width: navSpacing),

                          // DÉPENSES
                          InkWell(
                            onTap: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _expenseScreen(),
                                ),
                              );

                              if (result == true) {
                                await refreshDashboard();
                              }
                            },
                            child: SizedBox(
                              width: 90,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shopping_cart_outlined,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    context.tr('expenses'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(width: navSpacing),

                          // SUIVI DE PRODUCTION
                          InkWell(
                            key: const Key('topProductionTrackingButton'),
                            onTap: _openProductionTracking,
                            child: SizedBox(
                              width: 140,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.monitor_heart_outlined,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    context.tr('production_tracking'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(width: navSpacing),

                          // MOUVEMENTS
                          InkWell(
                            onTap: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddMouvementScreen(
                                    apiService: apiService,
                                  ),
                                ),
                              );

                              if (result == true) {
                                await refreshDashboard();
                              }
                            },
                            child: SizedBox(
                              width: 105,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.swap_horiz,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    context.tr('movements'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(width: navSpacing),

                          // FACTURATION
                          InkWell(
                            onTap: _openClients,
                            child: SizedBox(
                              width: 92,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    context.tr('billing'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          SizedBox(width: navSpacing),

                          // HISTORIQUE
                          InkWell(
                            onTap: _openHistory,
                            child: SizedBox(
                              width: 80,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    context.tr('history'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(width: 4),

                        // DÉCONNEXION
                        InkWell(
                          onTap: _logout,
                          child: SizedBox(
                            width: screenWidth < 700 ? 44 : 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.logout,
                                  color: Colors.white70,
                                  size: 25,
                                ),
                                if (screenWidth >= 700) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    context.tr('logout'),
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      body: LayoutBuilder(builder: (context, constraints) => Column(children: [
        if(apiService is FarmerApiService && (apiService as FarmerApiService).runtime.warning!=null)
          Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
            color:const Color(0xFFFFF4DF),child:Text((apiService as FarmerApiService).runtime.warning!,
              key:const Key('farmer-online-only-notice'),style:const TextStyle(color:Color(0xFF694A17)))),
        if(apiService.lastOperationMessage!=null) Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
          child:Text(apiService.lastOperationMessage!,key:const Key('last-operation-receipt'))),
        _dashboardHeading(constraints.maxHeight),
        Expanded(child: data == null
          ? Center(child: isLoading
              ? const CircularProgressIndicator()
              : Padding(padding: const EdgeInsets.all(24), child: Column(
                  mainAxisSize: MainAxisSize.min, children: [
                    Text(loadError ?? 'Données indisponibles.', textAlign: TextAlign.center),
                    TextButton(onPressed: _refreshAll, child: const Text('Réessayer')),
                  ])))
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              if (isLoading) const LinearProgressIndicator(),
              if (isLoading) const Padding(padding: EdgeInsets.all(8), child: Text(
                'Actualisation en cours : les données précédentes restent affichées.')),
              if (loadError != null) Padding(padding: const EdgeInsets.all(8),
                child: Text(loadError!, style: TextStyle(color: Colors.orange.shade800))),
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool horizontal = constraints.maxWidth >= 900;

                  Widget especeFilter() {
                    return DropdownButtonFormField<int>(
                      key: ValueKey('dashboardSpecies:$selectedEspeceId'),
                      isExpanded: true,

                      value: selectedEspeceId ?? 0,
                      decoration: InputDecoration(
                        labelText: context.tr('species'),
                        prefixIcon: const Icon(Icons.pets, color: Colors.green),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE0E6EA),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF0B4F7C),
                            width: 1.5,
                          ),
                        ),
                      ),
                      items: [
                        DropdownMenuItem<int>(
                          value: 0,
                          child: Text(context.tr('all_species')),
                        ),
                        ...especes.map<DropdownMenuItem<int>>((e) {
                          return DropdownMenuItem<int>(
                            value: _intValue(e["id"])!,
                            child: Text(e["nom"].toString()),
                          );
                        }),
                      ],
                      onChanged: isLoading ? null : (value) {
                        setState(() {
                          selectedEspeceId = value == 0 ? null : value;
                          selectedLotId = null;
                        });

                        fetchDashboardByEspece(value == 0 ? null : value);
                      },
                    );
                  }

                  Widget lotFilter() {
                    return DropdownButtonFormField<int?>(
                      key: ValueKey('dashboardLot:$selectedLotId'),

                      isExpanded: true,


                      value: selectedLotId,
                      decoration: InputDecoration(
                        labelText: context.tr('batch'),
                        prefixIcon: const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFF0B4F7C),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE0E6EA),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF0B4F7C),
                            width: 1.5,
                          ),
                        ),
                      ),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(context.tr('all_lots')),
                        ),
                        ...filteredLots.map((lot) {
                          return DropdownMenuItem<int?>(
                            value: lot["id"],
                            child: Text(lot["nom"].toString()),
                          );
                        }),
                      ],
                      onChanged: isLoading ? null : (value) {
                        setState(() {
                          selectedLotId = value;
                        });

                        if (value == null) {
                          fetchDashboardByEspece(selectedEspeceId);
                        } else {
                          fetchLotDetail(value);
                        }
                      },
                    );
                  }

                  if (horizontal) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 430, child: especeFilter()),
                        const SizedBox(width: 32),
                        SizedBox(width: 430, child: lotFilter()),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      especeFilter(),
                      const SizedBox(height: 10),
                      lotFilter(),
                    ],
                  );
                },
              ),

              const SizedBox(height: 22),

              LayoutBuilder(
                builder: (context, constraints) {
                  int columns;

                  if (constraints.maxWidth >= 1400) {
                    // Grand écran : 5 cards sur une ligne
                    columns = 5;
                  } else if (constraints.maxWidth >= 1100) {
                    // écran moyen : 5 cards sur une ligne
                    columns = 5;
                  } else if (constraints.maxWidth >= 800) {
                    // écran réduit : 3 cards par ligne
                    columns = 3;
                  } else if (constraints.maxWidth >= 550) {
                    // Tablette : 2 cards par ligne
                    columns = 2;
                  } else {
                    // Téléphone : 1 card par ligne
                    columns = 1;
                  }

                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: ((constraints.maxWidth - 16 * (columns - 1)) / columns / 190) /
                        (MediaQuery.textScalerOf(context).scale(24) / 24).clamp(1.0, 2.0),
                    children: [
                      buildCard(
                        context.tr('stock_total'),
                        kpis["stock"] ?? kpis["stock_total"],
                        Icons.inventory_2,
                        Colors.green,
                        () {
                          if (selectedLotId == null) {
                            showError(context.tr('choose_lot'));
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StockDetailScreen(
                                apiService: apiService,
                                lotId: selectedLotId!,
                              ),
                            ),
                          );
                        },
                        unit: context.tr('units'),
                      ),
                      buildCard(
                        context.tr('revenue'),
                        kpis["chiffre_affaires"],
                        Icons.trending_up,
                        Colors.blue,
                        () {
                          if (selectedEspeceId == null) {
                            showError(context.tr('species_required'));
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CADetailScreen(
                                apiService: apiService,
                                especeId: selectedEspeceId!,
                              ),
                            ),
                          );
                        },
                        isMoney: true,
                      ),
                      buildCard(
                        context.tr('expenses'),
                        kpis["depenses"],
                        Icons.account_balance_wallet,
                        Colors.orange,
                        () {
                          if (selectedLotId == null) {
                            showError(context.tr('choose_lot'));
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DepenseDetailScreenX(
                                apiService: apiService,
                                lotId: selectedLotId!,
                              ),
                            ),
                          );
                        },
                        isMoney: true,
                      ),
                      buildCard(
                        'Solde / CA (hors achats)',
                        operatingBalanceRate(kpis)?.toStringAsFixed(1),
                        Icons.pie_chart,
                        Colors.deepPurple,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PerformanceScreen(apiService: apiService),
                            ),
                          );
                        },
                        unit: '% · pas un bénéfice',
                      ),
                      buildCard(
                        context.tr('client_balance'),
                        totalDettes,
                        Icons.credit_card,
                        Colors.teal,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  DettesScreen(apiService: apiService),
                            ),
                          );
                        },
                        isMoney: true,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 40),

              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isLargeScreen = constraints.maxWidth >= 900;

                  // ================= CALENDRIER =================
                  Widget calendarCard = Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_month,
                              color: Color(0xFF0B4F7C),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr('task_calendar'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0B4F7C),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isLargeScreen && _mayPlanTasks)
                              ElevatedButton.icon(
                                onPressed: _addTask,
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(context.tr('add')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE8F5E9),
                                  foregroundColor: const Color(0xFF168A45),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TableCalendar(
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2030, 12, 31),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) {
                            return isSameDay(_selectedDay, day);
                          },
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                            });

                            final key = getDateKey(selectedDay);
                            final tasks = events[key] ?? [];

                            if (tasks.isNotEmpty) {
                              _showTasksForDay(selectedDay);
                            }
                          },
                          eventLoader: (day) {
                            final key = getDateKey(day);
                            return events[key] ?? [];
                          },
                          daysOfWeekHeight: 20,
                          rowHeight: 30,
                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: true,
                            defaultTextStyle: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF455A64),
                            ),
                            weekendTextStyle: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF607D8B),
                            ),
                            outsideTextStyle: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB0BEC5),
                            ),
                            todayDecoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            todayTextStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                            selectedDecoration: const BoxDecoration(
                              color: Color(0xFF0B4F7C),
                              shape: BoxShape.circle,
                            ),
                            selectedTextStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            markersMaxCount: 1,
                            markerDecoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            markerSize: 4,
                            markerMargin: const EdgeInsets.only(top: 1),
                            cellMargin: const EdgeInsets.all(3),
                          ),
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            leftChevronIcon: Icon(
                              Icons.chevron_left,
                              color: Color(0xFF0B4F7C),
                            ),
                            rightChevronIcon: Icon(
                              Icons.chevron_right,
                              color: Color(0xFF0B4F7C),
                            ),
                            titleTextStyle: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0B4F7C),
                            ),
                            headerPadding: EdgeInsets.symmetric(vertical: 2),
                          ),
                          daysOfWeekStyle: const DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF78909C),
                            ),
                            weekendStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF78909C),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );

                  // ================= TÂCHES DU JOUR =================
                  final tasksForDay = _getTasksForDay();

                  Widget tasksCard = Container(
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ================= TITRE =================
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              color: Color(0xFF0B4F7C),
                              size: 22,
                            ),
                            const SizedBox(width: 8),

                            Expanded(
                              child: Text(
                                context.tr('today_tasks'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0B4F7C),
                                ),
                              ),
                            ),

                            // ================= NAVIGATION TÂCHES =================
                            if (tasksForDay.length > 3) ...[
                              IconButton(
                                tooltip: context.tr('up'),
                                icon: const Icon(
                                  Icons.keyboard_arrow_up,
                                  color: Color(0xFF0B4F7C),
                                ),
                                onPressed: () {
                                  if (!_tasksScrollController.hasClients)
                                    return;

                                  final current = _tasksScrollController.offset;

                                  final target = (current - 180).clamp(
                                    0.0,
                                    _tasksScrollController
                                        .position
                                        .maxScrollExtent,
                                  );

                                  _tasksScrollController.animateTo(
                                    target,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: context.tr('down'),
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Color(0xFF0B4F7C),
                                ),
                                onPressed: () {
                                  if (!_tasksScrollController.hasClients)
                                    return;

                                  final current = _tasksScrollController.offset;

                                  final target = (current + 180).clamp(
                                    0.0,
                                    _tasksScrollController
                                        .position
                                        .maxScrollExtent,
                                  );

                                  _tasksScrollController.animateTo(
                                    target,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                  );
                                },
                              ),
                            ],

                            // ================= AJOUT SUR PETIT ÉCRAN =================
                            if (!isLargeScreen && _mayPlanTasks)
                              IconButton(
                                tooltip: context.tr('add_task'),
                                onPressed: _addTask,
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Color(0xFF168A45),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // ================= CONTENU =================
                        if (tasksForDay.isEmpty)
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F9FB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE5EAF0),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.event_available,
                                    size: 34,
                                    color: Color(0xFF90A4AE),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    context.tr('no_task_planned'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF607D8B),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    context.tr('free_day'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF90A4AE),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.builder(
                              controller: _tasksScrollController,
                              physics: const ClampingScrollPhysics(),
                              itemCount: tasksForDay.length,
                              itemBuilder: (context, index) {
                                final task = tasksForDay[index];

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Dismissible(
                                    key: Key(task["id"].toString()),
                                    direction: DismissDirection.none,
                                    onDismissed: (_) async {
                                      if(!await _cancelTask(task)) return;
                                      await loadTasks();

                                      if (!mounted) return;

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text("Tâche annulée — historique conservé"),
                                        ),
                                      );
                                    },
                                    background: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: const Icon(
                                        Icons.cancel_outlined,
                                        color: Colors.white,
                                      ),
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FBFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFFE3EAF0),
                                        ),
                                      ),
                                      child: ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.check_circle_outline,
                                          color: Colors.green,
                                        ),
                                        title: Text(
                                          task["title"],
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        trailing: _taskCancellationButton(task),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  );

                  // ================= DISPOSITION =================
                  if (isLargeScreen) {
                    return SizedBox(
                      height: 355,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: calendarCard),
                          const SizedBox(width: 16),
                          Expanded(child: tasksCard),
                        ],
                      ),
                    );
                  }

                  // ================= PETIT ÉCRAN =================
                  return Column(
                    children: [
                      calendarCard,
                      const SizedBox(height: 12),
                      SizedBox(height: 310, child: tasksCard),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      )),
      ])),
    );
  }
}
