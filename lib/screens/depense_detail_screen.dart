import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/detail_widgets.dart';

class DepenseDetailScreenX extends StatefulWidget {
  final ApiService apiService;
  final int lotId;
  final String? especeNom;
  final String? lotNom;
  const DepenseDetailScreenX({super.key, required this.apiService, required this.lotId, this.especeNom, this.lotNom});
  @override State<DepenseDetailScreenX> createState() => _DepenseDetailScreenXState();
}

class _DepenseDetailScreenXState extends State<DepenseDetailScreenX> {
  List<dynamic> data = [];
  bool isLoading = true;
  String? error;
  String? _especeNom;
  String? _lotNom;
  final colors = const [TerreEtOrColors.gold, Color(0xFFD85B4B), TerreEtOrColors.teal, Color(0xFF3D7FA1), Color(0xFF8A5A44), Color(0xFF7A6699)];
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final results = await Future.wait([
        widget.apiService.getDepenses(widget.lotId),
        widget.apiService.getLotDetail(widget.lotId),
      ]);
      final result = results[0] as List<dynamic>;
      final lot = results[1] as Map<String, dynamic>;
      if (!mounted) return;
      result.sort((a,b) => _num(b['total']).compareTo(_num(a['total'])));
      setState(() {
        data = result;
        _especeNom = widget.especeNom ?? lot['espece_nom']?.toString();
        _lotNom = widget.lotNom ?? lot['nom']?.toString();
        isLoading = false;
        error = null;
      });
    } catch(e) { if(!mounted)return; setState(() { error=e.toString(); isLoading=false; }); }
  }
  double _num(dynamic value) => (value as num?)?.toDouble() ?? 0;
  double get total =>
      data.fold<double>(0, (sum, item) => sum + _num(item['total']));
  String _name(dynamic item) => item['categorie__nom']?.toString() ?? 'Autre';
  String _money(double value) => AppSettings.instance.formatMoney(value, decimals: 0);
  IconData _icon(String name) { final n=name.toUpperCase(); if(n.contains('ALIMENT'))return Icons.grass; if(n.contains('MEDIC'))return Icons.medication_outlined; if(n.contains('TRANSPORT'))return Icons.local_shipping_outlined; if(n.contains('MAIN')||n.contains('SALAIRE'))return Icons.groups_outlined; if(n.contains('ENTRETIEN')||n.contains('MAINT'))return Icons.handyman_outlined; return Icons.category_outlined; }

  @override Widget build(BuildContext context) {
    if(isLoading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(error!=null)return Scaffold(appBar:AppBar(title:Text(context.tr('expenses'))),body:Center(child:Text(error!)));
    if(data.isEmpty)return Scaffold(appBar:AppBar(title:Text(context.tr('expenses'))),body:Center(child:Text(context.tr('no_data'))));
    final main=data.first; final mainValue=_num(main['total']);
    final selection = [_especeNom, _lotNom]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${context.tr('expenses')} / ${context.tr('category')}'),
          if (selection.isNotEmpty)
            Text(selection, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: RefreshIndicator(onRefresh:load,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
        LayoutBuilder(builder:(context,c)=>GridView.count(crossAxisCount:c.maxWidth>=700?2:1,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:12,crossAxisSpacing:12,childAspectRatio:c.maxWidth>=700?2.5:2.8,children:[
          DetailMetricCard(label:'Dépenses du lot',value:_money(total),caption:'${data.length} catégories',icon:Icons.account_balance_wallet_outlined,color:const Color(0xFFD85B4B)),
          DetailMetricCard(label:'Poste principal',value:_name(main),caption:'${total==0?0:(mainValue/total*100).toStringAsFixed(0)} % · ${_money(mainValue)}',icon:_icon(_name(main)),color:TerreEtOrColors.gold),
        ])),
        const SizedBox(height:14),
        DetailSection(title:'Répartition par catégorie',subtitle:'Dépenses du lot préalablement sélectionné',child:LayoutBuilder(builder:(context,c){
          final chart=SizedBox(width:210,height:210,child:Stack(alignment:Alignment.center,children:[
            PieChart(PieChartData(centerSpaceRadius:58,sectionsSpace:3,sections:List.generate(data.length,(i){final value=_num(data[i]['total']);return PieChartSectionData(value:value,color:colors[i%colors.length],radius:36,title:total==0?'':'${(value/total*100).toStringAsFixed(0)}%',titleStyle:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.bold));}))),
            Column(mainAxisSize:MainAxisSize.min,children:[const Text('Total',style:TextStyle(color:TerreEtOrColors.muted,fontSize:12)),Text(_money(total),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15))]),
          ]));
          final list=Column(children:List.generate(data.length,(i){final item=data[i];final value=_num(item['total']);final pct=total==0?0.0:value/total;final color=colors[i%colors.length];return Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Row(children:[Container(width:38,height:38,decoration:BoxDecoration(color:color.withValues(alpha:.13),borderRadius:BorderRadius.circular(10)),child:Icon(_icon(_name(item)),color:color,size:20)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(_name(item),style:const TextStyle(fontWeight:FontWeight.w600))),Text(_money(value),style:const TextStyle(fontWeight:FontWeight.bold))]),const SizedBox(height:7),LinearProgressIndicator(value:pct,minHeight:7,borderRadius:BorderRadius.circular(8),backgroundColor:TerreEtOrColors.border.withValues(alpha:.55),color:color),const SizedBox(height:3),Text('${(pct*100).toStringAsFixed(1)} % du total',style:const TextStyle(fontSize:11,color:TerreEtOrColors.muted))]))]));}));
          return c.maxWidth>=700?Row(crossAxisAlignment:CrossAxisAlignment.center,children:[chart,const SizedBox(width:30),Expanded(child:list)]):Column(children:[chart,const SizedBox(height:12),list]);
        })),
      ])),
    );
  }
}
