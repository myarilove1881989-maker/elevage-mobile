import 'package:flutter/material.dart';
import '../services/farm_session.dart';
import '../l10n/app_localizations.dart';

enum FarmDestination {dashboard,billing,lots,purchases,sales,expenses,movements,history,agenda,production,settings,users,tutorial,logout}
const farmNavigationOrder=[FarmDestination.lots,FarmDestination.purchases,FarmDestination.expenses,
  FarmDestination.production,FarmDestination.movements,FarmDestination.billing,FarmDestination.history,
  FarmDestination.agenda,FarmDestination.settings,FarmDestination.tutorial,FarmDestination.logout];
const farmDestinationLabels={FarmDestination.dashboard:'Tableau de bord',FarmDestination.lots:'Lots',
  FarmDestination.purchases:'Achats',FarmDestination.expenses:'Dépenses',FarmDestination.production:'Suivi de production',
  FarmDestination.movements:'Mouvements',FarmDestination.billing:'Facturation',FarmDestination.history:'Historique',
  FarmDestination.agenda:'Agenda',FarmDestination.settings:'Paramètres',FarmDestination.tutorial:'Tuto',
  FarmDestination.logout:'Quitter',FarmDestination.sales:'Ventes',FarmDestination.users:'Gestion des utilisateurs'};
const farmDestinationIcons={FarmDestination.lots:Icons.inventory_2_outlined,FarmDestination.purchases:Icons.shopping_bag_outlined,
  FarmDestination.expenses:Icons.receipt_long_outlined,FarmDestination.production:Icons.monitor_heart_outlined,
  FarmDestination.movements:Icons.swap_horiz,FarmDestination.billing:Icons.request_quote_outlined,
  FarmDestination.history:Icons.history,FarmDestination.agenda:Icons.event_note_outlined,
  FarmDestination.settings:Icons.settings_outlined,FarmDestination.tutorial:Icons.menu_book_outlined,FarmDestination.logout:Icons.logout};
String navigationLabel(BuildContext context,FarmDestination destination){
  if(AppLocalizations.of(context).languageCode!='en')return farmDestinationLabels[destination]!;
  return {FarmDestination.lots:'Batches',FarmDestination.purchases:'Purchases',FarmDestination.expenses:'Expenses',
    FarmDestination.production:'Production tracking',FarmDestination.movements:'Movements',FarmDestination.billing:'Billing',
    FarmDestination.history:'History',FarmDestination.agenda:'Tasks',FarmDestination.settings:'Settings',
    FarmDestination.tutorial:'Tutorial',FarmDestination.logout:'Log out'}[destination]!;
}

/// Both menus use this exact ordered catalogue, icons, access rules and callbacks.
class FarmNavigation extends StatefulWidget {
  const FarmNavigation({super.key,required this.actions,this.session,this.labels=const {},this.horizontal=false,this.beforeNavigate});
  final Map<FarmDestination,VoidCallback> actions;
  final FarmSession? session;
  final Map<FarmDestination,String> labels;
  final bool horizontal;
  final VoidCallback? beforeNavigate;
  @override State<FarmNavigation> createState()=>_FarmNavigationState();
}
class _FarmNavigationState extends State<FarmNavigation>{
  final scroll=ScrollController();
  @override void dispose(){scroll.dispose();super.dispose();}
  bool visible(FarmDestination d){
    if(!widget.actions.containsKey(d))return false;
    final rights=widget.session?.permissions;
    switch(d){
      case FarmDestination.purchases:return rights?.allows('purchases.create')==true;
      case FarmDestination.expenses:return rights?.allows('expenses.create')==true;
      case FarmDestination.movements:return ['animal_sales.create','mortality.create','births.create','donations.create','thefts.create'].any((x)=>rights?.allows(x)==true);
      case FarmDestination.agenda:return rights?.allows('agenda.read')==true || rights?.allows('agenda.plan')==true;
      default:return true; // business reads remain available to active members
    }
  }
  @override Widget build(BuildContext context){
    final items=[for(final d in farmNavigationOrder)if(visible(d))d];
    void open(FarmDestination d){widget.beforeNavigate?.call();widget.actions[d]!();}
    if(!widget.horizontal)return Column(mainAxisSize:MainAxisSize.min,children:[for(final d in items)ListTile(
      key:ValueKey('navigation-${d.name}'),leading:Icon(farmDestinationIcons[d]),
      title:Text(widget.labels[d]??navigationLabel(context,d)),onTap:()=>open(d))]);
    return Scrollbar(controller:scroll,thumbVisibility:true,child:SingleChildScrollView(
      controller:scroll,scrollDirection:Axis.horizontal,padding:const EdgeInsets.fromLTRB(8,4,8,12),
      child:Row(children:[for(final d in items)Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:TextButton.icon(
        key:d==FarmDestination.production?const Key('topProductionTrackingButton'):ValueKey('navigation-${d.name}-horizontal'),
        onPressed:()=>open(d),icon:Icon(farmDestinationIcons[d]),label:Text(widget.labels[d]??navigationLabel(context,d)),
        style:TextButton.styleFrom(minimumSize:const Size(0,44))))])));
  }
}
