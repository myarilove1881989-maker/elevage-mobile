import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/farm_session.dart';
import '../services/physical_stock_summary.dart';
import 'dashboard_kpi_card.dart';

/// Server presentation only. Never reads/writes a tablet cache or an outbox.
class AndroidOnlineStockCards extends StatefulWidget {
  const AndroidOnlineStockCards({super.key,required this.api,required this.session,this.species,this.lot,required this.revision});
  final ApiService api;
  final FarmSession session;
  final int? species,lot;
  final int revision;
  @override State<AndroidOnlineStockCards> createState()=>_AndroidOnlineStockCardsState();
}
class _AndroidOnlineStockCardsState extends State<AndroidOnlineStockCards>{
  Map<String,dynamic>? feed,vaccine;
  String? identity;
  int generation=0;
  Timer? clock;
  bool loading=true,failed=false;
  @override void initState(){super.initState();load();clock=Timer.periodic(const Duration(minutes:1),(_){if(mounted)setState((){});});}
  @override void didUpdateWidget(AndroidOnlineStockCards old){
    super.didUpdateWidget(old);
    if(old.revision!=widget.revision || old.session!=widget.session || old.api!=widget.api)load();
  }
  @override void dispose(){clock?.cancel();super.dispose();}
  Future<void> load()async{
    final ticket=++generation,captured=ApiService.sessionIdentity;
    setState((){loading=true;failed=false;feed=null;vaccine=null;identity=null;});
    try{
      final snapshots=await Future.wait([widget.api.get('/feed-supplies/?presentation=1'),widget.api.get('/vaccine-supplies/')]);
      if(!mounted || ticket!=generation)return;
      if(captured!=ApiService.sessionIdentity){setState((){loading=false;failed=true;});return;}
      for(final snapshot in snapshots){
        if(snapshot is! Map || snapshot['exploitation']!=widget.session.farmId || snapshot['products'] is! List)throw StateError('Invalid stock scope');
      }
      if(snapshots[1]['vials'] is! List)throw StateError('Invalid vaccine snapshot');
      // Validate all presentation calculations before exposing either snapshot.
      feedSummary(snapshots[0] as Map,species:widget.species,lot:widget.lot);
      vaccineSummary(snapshots[1] as Map,DateTime.now().toUtc(),species:widget.species,lot:widget.lot);
      setState((){feed=Map<String,dynamic>.from(snapshots[0]);vaccine=Map<String,dynamic>.from(snapshots[1]);identity=captured;loading=false;});
    }catch(_){if(mounted && ticket==generation)setState((){loading=false;failed=true;});}
  }
  @override Widget build(BuildContext context){
    if(loading)return const Padding(padding:EdgeInsets.all(12),child:LinearProgressIndicator());
    if(failed || identity!=ApiService.sessionIdentity || feed==null || vaccine==null){
      return const Padding(padding:EdgeInsets.all(12),child:Text('Stocks physiques indisponibles. Aucun stock nul ne peut être déduit de cette absence de réponse.'));
    }
    final fs=feedSummary(feed!,species:widget.species,lot:widget.lot);
    final vs=vaccineSummary(vaccine!,DateTime.now().toUtc(),species:widget.species,lot:widget.lot);
    Widget card(String title,IconData icon,Widget content)=>SizedBox(height:235,child:DashboardKpiCard(title:title,icon:icon,color:Colors.blueGrey,content:content));
    final cards=[
      card('Stock physique d’aliments',Icons.grass,Text('${fs['confirmed']} kg\nLecture serveur',textAlign:TextAlign.center)),
      card('Stock physique de vaccins',Icons.vaccines_outlined,Text('${vs['physical']} doses · ${vs['usable']} utilisables\nLecture serveur',textAlign:TextAlign.center)),
    ];
    return LayoutBuilder(builder:(context,box)=>box.maxWidth>=600
      ? Row(children:[Expanded(child:cards[0]),const SizedBox(width:12),Expanded(child:cards[1])])
      : Column(children:[cards[0],const SizedBox(height:12),cards[1]]));
  }
}
