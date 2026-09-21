import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/detail_widgets.dart';

class LotDetailScreen extends StatefulWidget {
  final ApiService apiService; final int lotId;
  const LotDetailScreen({super.key,required this.apiService,required this.lotId});
  @override State<LotDetailScreen> createState()=>_LotDetailScreenState();
}

class _LotDetailScreenState extends State<LotDetailScreen>{
  Map<String,dynamic>? lot; bool isLoading=true;
  @override void initState(){super.initState();fetchLot();}
  Future<void> fetchLot() async{try{final result=await widget.apiService.getLotDetail(widget.lotId);if(!mounted)return;setState((){lot=result;isLoading=false;});}catch(_){if(mounted)setState(()=>isLoading=false);}}
  Future<bool> confirmDelete() async=>await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:Text(context.tr('confirmation')),content:Text(context.tr('delete_item')),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(context.tr('cancel'))),TextButton(onPressed:()=>Navigator.pop(context,true),child:Text(context.tr('delete')))]))??false;
  void message(String value)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));
  double numValue(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.').trim()) ?? 0;
    }
    return 0;
  }

  int? intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
  String money(dynamic v)=>AppSettings.instance.formatMoney(numValue(v),decimals:0);

  @override Widget build(BuildContext context){
    if(isLoading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(lot==null)return const Scaffold(body:Center(child:Text('Impossible de charger ce lot')));
    final purchases=List<dynamic>.from(lot!['achats']??[]);
    final movements=List<dynamic>.from(lot!['mouvements']??[]).where((m)=>m['type_mouvement']!='ACHAT').toList();
    final expenses=List<dynamic>.from(lot!['depenses']??[]);
    final initial=purchases.fold<double>(0,(s,a)=>s+numValue(a['quantite']));
    final outgoing=movements.fold<double>(0,(s,m)=>s+numValue(m['quantite']));
    final expenseTotal=expenses.fold<double>(0,(s,d)=>s+numValue(d['montant']));
    return Scaffold(appBar:AppBar(title:Text(lot!['nom']?.toString()??'Lot')),body:RefreshIndicator(onRefresh:fetchLot,child:LayoutBuilder(builder:(context,constraints)=>ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18),border:const Border(left:BorderSide(color:TerreEtOrColors.gold,width:5))),child:Row(children:[Container(width:52,height:52,decoration:BoxDecoration(color:TerreEtOrColors.paleGold,borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.inventory_2_outlined,color:TerreEtOrColors.gold)),const SizedBox(width:13),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(lot!['espece_nom']?.toString()??'',style:const TextStyle(color:TerreEtOrColors.teal,fontWeight:FontWeight.w600)),Text(lot!['nom']?.toString()??'',style:const TextStyle(color:TerreEtOrColors.ink,fontSize:21,fontWeight:FontWeight.bold)),Text('Début : ${lot!['date_debut']??''}',style:const TextStyle(color:TerreEtOrColors.muted,fontSize:12))])),Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:TerreEtOrColors.green.withValues(alpha:.12),borderRadius:BorderRadius.circular(20)),child:const Text('ACTIF',style:TextStyle(color:TerreEtOrColors.green,fontWeight:FontWeight.bold,fontSize:11)))])),
      const SizedBox(height:14),
      GridView.count(crossAxisCount:constraints.maxWidth>=850?4:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:constraints.maxWidth<430?1.2:1.55,children:[
        DetailMetricCard(label:'Stock initial',value:initial.toStringAsFixed(0),caption:'unités',icon:Icons.inventory_outlined,color:const Color(0xFF3D7FA1)),
        DetailMetricCard(label:'Stock actuel',value:numValue(lot!['stock']).toStringAsFixed(0),caption:'unités disponibles',icon:Icons.check_circle_outline,color:TerreEtOrColors.green),
        DetailMetricCard(label:'Sorties',value:outgoing.toStringAsFixed(0),caption:'unités',icon:Icons.swap_horiz,color:TerreEtOrColors.gold),
        DetailMetricCard(label:'Dépenses',value:money(expenseTotal),icon:Icons.receipt_long_outlined,color:const Color(0xFFD85B4B)),
      ]),
      const SizedBox(height:14),
      DetailSection(title:'Historique du lot',subtitle:'Achats, mouvements et dépenses',child:Column(children:[
        if(purchases.isEmpty&&movements.isEmpty&&expenses.isEmpty)Text(context.tr('no_data')),
        ...purchases.map((a)=>_event(icon:Icons.shopping_bag_outlined,color:TerreEtOrColors.gold,title:context.tr('purchase'),subtitle:'${a['quantite']??0} unités · ${money(a['prix_total'])}',date:a['date']?.toString()??'',onDelete:()async{if(!await confirmDelete())return;final id=intValue(a['id']);if(id==null)return;if(await widget.apiService.deleteAchat(id)){if(mounted){message('Lot supprimé');Navigator.pop(context,true);}}})),
        ...movements.map((m)=>_event(icon:Icons.swap_horiz,color:_movementColor(m['type_mouvement']?.toString()),title:m['type_mouvement']?.toString()??'Mouvement',subtitle:'${m['quantite']??0} unités${m['prix_unitaire']!=null?' · PU ${money(m['prix_unitaire'])}':''}',date:m['date']?.toString()??'',onDelete:()async{if(!await confirmDelete())return;final id=intValue(m['id']);if(id!=null&&await widget.apiService.deleteMouvement(id)){message('Supprimé');fetchLot();}})),
        ...expenses.map((d)=>_event(icon:Icons.receipt_long_outlined,color:const Color(0xFFD85B4B),title:d['categorie_nom']?.toString()??'Dépense',subtitle:money(d['montant']),date:d['date']?.toString()??'',onDelete:()async{if(!await confirmDelete())return;final id=intValue(d['id']);if(id!=null&&await widget.apiService.deleteDepense(id)){message('Supprimé');fetchLot();}})),
      ])),
    ]))));
  }
  Color _movementColor(String? type){switch(type){case'VENTE':return TerreEtOrColors.green;case'MORTALITE':return const Color(0xFFD85B4B);case'VOL':return const Color(0xFF8A5A44);default:return const Color(0xFF3D7FA1);}}
  Widget _event({required IconData icon,required Color color,required String title,required String subtitle,required String date,required VoidCallback onDelete})=>Container(padding:const EdgeInsets.symmetric(vertical:9),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:TerreEtOrColors.border))),child:Row(children:[Container(width:38,height:38,decoration:BoxDecoration(color:color.withValues(alpha:.12),borderRadius:BorderRadius.circular(10)),child:Icon(icon,color:color,size:20)),const SizedBox(width:11),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w600)),Text(subtitle,style:const TextStyle(color:TerreEtOrColors.muted,fontSize:12))])),Text(date,style:const TextStyle(color:TerreEtOrColors.muted,fontSize:11)),IconButton(onPressed:onDelete,icon:const Icon(Icons.delete_outline,color:Color(0xFFD85B4B),size:20))]));
}
