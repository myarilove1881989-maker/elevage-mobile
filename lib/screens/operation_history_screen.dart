import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/operation_history.dart';
import '../widgets/operation_history_list.dart';
import 'owner_operation_history_screen.dart';
import '../theme/terre_et_or_theme.dart';

class OperationHistoryScreen extends StatefulWidget {
  const OperationHistoryScreen({super.key, required this.api,this.ownerActivity=false});
  final ApiService api;
  final bool ownerActivity;
  @override
  State<OperationHistoryScreen> createState() => _OperationHistoryScreenState();
}

class _OperationHistoryScreenState extends State<OperationHistoryScreen> {
  String typeFilter='',statusFilter='';
  List<OperationHistoryItem> get mergedItems {
    final values=<String,OperationHistoryItem>{for(final item in items) item.identity:item};
    for(final entry in widget.api.localOperations) {values[entry.operationId]=OperationHistoryItem.local(entry);}
    return values.values.where((item)=>(typeFilter.isEmpty || item.type==typeFilter) &&
      (statusFilter.isEmpty || item.status==statusFilter)).toList();
  }
  void changed() {if(mounted) setState(() {});}
  @override
  void dispose() {widget.api.sessionChanges?.removeListener(changed);super.dispose();}
  List<OperationHistoryItem> items = [];
  List<Map<String, dynamic>> loadedEvents = [];
  bool busy = false, failed = false;
  int page = 1;
  bool hasNext = false;
  String? displayedToken;
  @override
  void initState() {
    super.initState();
    widget.api.sessionChanges?.addListener(changed);
    _load();
  }

  Future<void> _load({bool next = false}) async {
    if (busy) return;
    final token = (ApiService.sessionIdentity);
    if (token == null) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final result = await widget.api.get(
        '/history/?page=${next ? page + 1 : 1}',
      );
      if (!mounted || token != (ApiService.sessionIdentity)) return;
      final events = (result['results'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        final merged = <Object?, Map<String, dynamic>>{
          if (next && displayedToken == token)
            for (final event in loadedEvents) event['id']: event,
          for (final event in events) event['id']: event,
        };
        loadedEvents = merged.values.toList();
        items = serverHistory(loadedEvents);
        page = next ? page + 1 : 1;
        hasNext = result['next'] != null;
        displayedToken = token;
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(data:terreEtOrTheme(context),child:Builder(builder:(context)=>Scaffold(
    appBar: AppBar(title: const Text('Historique')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if(widget.ownerActivity) OutlinedButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>OwnerOperationHistoryScreen(api:widget.api))),
          child:const Text('Activité complète des tablettes — propriétaire')),
        const TerreEtOrHeader(icon:Icons.history,title:'Historique',subtitle:'Retrouvez vos opérations et leur état'),
        DropdownButtonFormField<String>(initialValue:typeFilter,decoration:const InputDecoration(labelText:'Type d’opération'),
          items:[const DropdownMenuItem(value:'',child:Text('Toutes les opérations')),
            for(final type in {if(typeFilter.isNotEmpty)typeFilter,...items.map((e)=>e.type),...widget.api.localOperations.map((e)=>OperationHistoryItem.local(e).type)})
              DropdownMenuItem(value:type,child:Text(type))],onChanged:(value)=>setState(()=>typeFilter=value??'')),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(initialValue:statusFilter,decoration:const InputDecoration(labelText:'État'),
          items:[const DropdownMenuItem(value:'',child:Text('Tous les états')),
            for(final status in {if(statusFilter.isNotEmpty)statusFilter,...items.map((e)=>e.status),...widget.api.localOperations.map((e)=>OperationHistoryItem.local(e).status)})
              DropdownMenuItem(value:status,child:Text(status))],onChanged:(value)=>setState(()=>statusFilter=value??'')),
        const SizedBox(height:16),
        if (busy) const LinearProgressIndicator(),
        if (failed)
          const Text(
            'Lecture indisponible. Les événements déjà affichés restent conservés.',
          ),
        if (displayedToken == (ApiService.sessionIdentity) || widget.api.localOperations.isNotEmpty)
          OperationHistoryList(items: mergedItems),
        OutlinedButton(
          onPressed: busy ? null : _load,
          child: const Text('Actualiser'),
        ),
        if (hasNext)
          TextButton(
            onPressed: busy ? null : () => _load(next: true),
            child: const Text('Suivant'),
          ),
      ],
    ),
  )));
}
