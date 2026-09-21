import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/dette_client.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../theme/terre_et_or_theme.dart';
import '../widgets/detail_widgets.dart';
import 'client_detail_screen.dart';

class DettesScreen extends StatefulWidget {
  final ApiService apiService;
  const DettesScreen({super.key, required this.apiService});
  @override State<DettesScreen> createState() => _DettesScreenState();
}

class _DettesScreenState extends State<DettesScreen> {
  List<DetteClient> clients=[]; bool isLoading=true; String selectedFilter='ALL'; String searchQuery='';
  @override void initState(){super.initState();loadData();}
  Future<void> loadData() async { try { final result=await widget.apiService.getDettesClients(); result.sort((a,b)=>b.reste.compareTo(a.reste)); if(!mounted)return; setState((){clients=result;isLoading=false;}); } catch(e){if(!mounted)return;setState(()=>isLoading=false);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Erreur de chargement des soldes clients')));} }
  List<DetteClient> get filtered => clients.where((c){final status=selectedFilter=='ALL'||c.statut==selectedFilter;final q=searchQuery.toLowerCase();final match=q.isEmpty||c.nom.toLowerCase().contains(q)||(c.telephone??'').toLowerCase().contains(q);return status&&match;}).toList();
  Color color(String status)=>status=='PAYE'?TerreEtOrColors.green:status=='PARTIEL'?TerreEtOrColors.gold:const Color(0xFFD85B4B);
  String money(double value)=>AppSettings.instance.formatMoney(value,decimals:0);
  String label(String filter){if(filter=='ALL')return'Tous';if(filter=='PAYE')return'Payés';if(filter=='PARTIEL')return'Partiels';return'Impayés';}

  @override Widget build(BuildContext context){
    final list=filtered; final billed=clients.fold<double>(0,(s,c)=>s+c.totalFacture);final paid=clients.fold<double>(0,(s,c)=>s+c.totalPaye);final due=clients.fold<double>(0,(s,c)=>s+c.reste);
    return Scaffold(appBar:AppBar(title:Text(context.tr('customer_debts'))),body:isLoading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:loadData,child:LayoutBuilder(builder:(context,constraints)=>ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
      GridView.count(crossAxisCount:constraints.maxWidth>=760?3:constraints.maxWidth>=480?3:1,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:constraints.maxWidth<480?3.0:1.45,children:[
        DetailMetricCard(label:'Total facturé',value:money(billed),icon:Icons.receipt_long_outlined,color:const Color(0xFF3D7FA1)),
        DetailMetricCard(label:'Total payé',value:money(paid),icon:Icons.check_circle_outline,color:TerreEtOrColors.green),
        DetailMetricCard(label:'Solde à recevoir',value:money(due),icon:Icons.account_balance_wallet_outlined,color:due>0?const Color(0xFFD85B4B):TerreEtOrColors.green),
      ]),
      const SizedBox(height:14),
      TextField(decoration:InputDecoration(hintText:context.tr('search_name_phone'),prefixIcon:const Icon(Icons.search)),onChanged:(v)=>setState(()=>searchQuery=v)),
      const SizedBox(height:10),
      Wrap(spacing:8,runSpacing:8,children:['ALL','PAYE','PARTIEL','IMPAYE'].map((f)=>ChoiceChip(label:Text(label(f)),selected:selectedFilter==f,selectedColor:TerreEtOrColors.paleGold,onSelected:(_)=>setState(()=>selectedFilter=f))).toList()),
      const SizedBox(height:14),
      if(list.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:70),child:Center(child:Text('Aucun solde client trouvé')))
      else ...list.map((c)=>_clientCard(c)),
    ]))));
  }

  Widget _clientCard(DetteClient client) {
    final statusColor = color(client.statut);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ClientDetailScreen(
              clientId: client.id,
              nom: client.nom,
              telephone: client.telephone ?? '',
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final identity = Row(
                children: [
                  CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: .13),
                    child: Icon(Icons.person_outline, color: statusColor),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.nom,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if ((client.telephone ?? '').isNotEmpty)
                          Text(
                            client.telephone ?? '',
                            style: const TextStyle(
                              color: TerreEtOrColors.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
              final amounts = Row(
                children: [
                  Expanded(
                    child: _amount(
                      'Facturé',
                      client.totalFacture,
                      const Color(0xFF3D7FA1),
                    ),
                  ),
                  Expanded(
                    child: _amount(
                      'Payé',
                      client.totalPaye,
                      TerreEtOrColors.green,
                    ),
                  ),
                  Expanded(
                    child: _amount('Reste', client.reste, statusColor),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      client.statut,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  children: [identity, const SizedBox(height: 12), amounts],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 230, child: identity),
                  const SizedBox(width: 16),
                  Expanded(child: amounts),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
  Widget _amount(String label,double value,Color color)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:TerreEtOrColors.muted,fontSize:11)),const SizedBox(height:3),FittedBox(fit:BoxFit.scaleDown,alignment:Alignment.centerLeft,child:Text(money(value),style:TextStyle(color:color,fontWeight:FontWeight.bold)))]);
}
