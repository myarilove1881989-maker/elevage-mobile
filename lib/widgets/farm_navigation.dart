import '../theme/design_system_v2.dart';
import 'v2_components.dart';
import 'package:flutter/material.dart';
import '../services/farm_session.dart';
import '../l10n/app_localizations.dart';

enum FarmDestination {dashboard,billing,lots,purchases,sales,expenses,movements,history,agenda,production,settings,users,tutorial,logout}
const farmNavigationOrder=[FarmDestination.users,FarmDestination.lots,FarmDestination.purchases,FarmDestination.expenses,
  FarmDestination.production,FarmDestination.movements,FarmDestination.billing,FarmDestination.history,
  FarmDestination.agenda,FarmDestination.settings,FarmDestination.tutorial,FarmDestination.logout];
const farmDestinationLabels={FarmDestination.dashboard:'Tableau de bord',FarmDestination.lots:'Lots',
  FarmDestination.purchases:'Achats',FarmDestination.expenses:'Dépenses',FarmDestination.production:'Production',
  FarmDestination.movements:'Mouvements',FarmDestination.billing:'Facturation',FarmDestination.history:'Historique',
  FarmDestination.agenda:'Agenda',FarmDestination.settings:'Paramètres',FarmDestination.tutorial:'Tuto',
  FarmDestination.logout:'Quitter',FarmDestination.sales:'Ventes',FarmDestination.users:'Gestion des utilisateurs'};
const farmDestinationIcons={FarmDestination.dashboard:Icons.home_outlined,FarmDestination.users:Icons.manage_accounts_outlined,FarmDestination.lots:Icons.inventory_2_outlined,FarmDestination.purchases:Icons.shopping_bag_outlined,
  FarmDestination.expenses:Icons.shopping_cart_outlined,FarmDestination.production:Icons.layers_outlined,
  FarmDestination.movements:Icons.swap_horiz,FarmDestination.billing:Icons.request_quote_outlined,
  FarmDestination.history:Icons.history,FarmDestination.agenda:Icons.event_note_outlined,
  FarmDestination.settings:Icons.settings_outlined,FarmDestination.tutorial:Icons.menu_book_outlined,FarmDestination.logout:Icons.logout};
String navigationLabel(BuildContext context,FarmDestination destination){
  if(AppLocalizations.of(context).languageCode!='en')return farmDestinationLabels[destination]!;
  return {FarmDestination.dashboard:'Dashboard',FarmDestination.users:'User management',FarmDestination.lots:'Batches',FarmDestination.purchases:'Purchases',FarmDestination.expenses:'Expenses',
    FarmDestination.production:'Production',FarmDestination.movements:'Movements',FarmDestination.billing:'Billing',
    FarmDestination.history:'History',FarmDestination.agenda:'Tasks',FarmDestination.settings:'Settings',
    FarmDestination.tutorial:'Tutorial',FarmDestination.logout:'Log out'}[destination]!;
}

const farmHorizontalNavigationOrder=[FarmDestination.purchases,FarmDestination.expenses,FarmDestination.production,FarmDestination.movements,FarmDestination.billing];

/// Both menus share icons, access rules and callbacks; utilities stay in the drawer.
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
      case FarmDestination.users:return widget.session?.role=='OWNER' && rights?.allows('users.manage')==true;
      case FarmDestination.purchases:return rights?.allows('purchases.create')==true;
      case FarmDestination.expenses:return rights?.allows('expenses.create')==true;
      case FarmDestination.movements:return ['animal_sales.create','mortality.create','births.create','donations.create','thefts.create'].any((x)=>rights?.allows(x)==true);
      case FarmDestination.agenda:return rights?.allows('agenda.read')==true || rights?.allows('agenda.plan')==true;
      default:return true; // business reads remain available to active members
    }
  }
  @override Widget build(BuildContext context){
    final order=widget.horizontal?farmHorizontalNavigationOrder:farmNavigationOrder;
    final items=[for(final d in order)if(visible(d))d];
    void open(FarmDestination d){widget.beforeNavigate?.call();widget.actions[d]!();}
    if(!widget.horizontal)return Column(mainAxisSize:MainAxisSize.min,children:[for(final d in items)ListTile(
      key:ValueKey('navigation-${d.name}'),leading:Icon(farmDestinationIcons[d]),
      title:Text(widget.labels[d]??navigationLabel(context,d)),onTap:()=>open(d))]);
    return SizedBox(height:52,child:LayoutBuilder(builder:(context,constraints){
      final padding=constraints.maxWidth>=1200?12.0:constraints.maxWidth>=800?8.0:6.0;
      return SingleChildScrollView(controller:scroll,scrollDirection:Axis.horizontal,
        child:ConstrainedBox(constraints:BoxConstraints(minWidth:constraints.maxWidth),
          child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[for(final d in items)
            Padding(padding:const EdgeInsets.symmetric(horizontal:2),child:TextButton.icon(
              key:d==FarmDestination.production?const Key('topProductionTrackingButton'):ValueKey('navigation-${d.name}-horizontal'),
              onPressed:()=>open(d),icon:Icon(farmDestinationIcons[d],size:18),
              label:Text(widget.labels[d]??navigationLabel(context,d),maxLines:1,softWrap:false),
              style:TextButton.styleFrom(foregroundColor:Colors.white,
                textStyle:const TextStyle(fontFamily:'Roboto',fontSize:15.5,fontWeight:FontWeight.w500),
                minimumSize:const Size(0,48),padding:EdgeInsets.symmetric(horizontal:padding),
                visualDensity:VisualDensity.compact)))
          ])));
    }));
  }
}


/// One compact row on desktop. The original drawer remains the adaptive menu.
class FarmTopBar extends StatelessWidget implements PreferredSizeWidget {
  const FarmTopBar({super.key,required this.actions,required this.connection,required this.onRefresh,required this.onLogout,this.session});
  final Map<FarmDestination,VoidCallback> actions;
  final Widget connection;
  final VoidCallback? onRefresh;
  final VoidCallback onLogout;
  final FarmSession? session;
  @override Size get preferredSize=>const Size.fromHeight(64);
  bool visible(FarmDestination d) {
    if(!actions.containsKey(d))return false;
    final rights=session?.permissions;
    if(d==FarmDestination.purchases)return rights?.allows('purchases.create')==true;
    if(d==FarmDestination.expenses)return rights?.allows('expenses.create')==true;
    if(d==FarmDestination.movements)return ['animal_sales.create','mortality.create','births.create','donations.create','thefts.create'].any((a)=>rights?.allows(a)==true);
    return true;
  }
  @override Widget build(BuildContext context)=>AppBar(automaticallyImplyLeading:false,toolbarHeight:64,
    backgroundColor:V2Colors.navy,foregroundColor:Colors.white,titleSpacing:8,
    title:LayoutBuilder(builder:(context,box){
      double labelWidth(String text, double size) {
        final painter=TextPainter(text:TextSpan(text:text,style:TextStyle(fontFamily:'Roboto',fontSize:size,fontWeight:FontWeight.w600)),textDirection:Directionality.of(context),textScaler:MediaQuery.textScalerOf(context))..layout();
        return painter.width;
      }
      final requiredWidth=48+labelWidth('Elev’Age',24)+32+88+48+12+labelWidth('Quitter',14)+64+
        farmHorizontalNavigationOrder.where(visible).fold<double>(0,(sum,d)=>sum+labelWidth(navigationLabel(context,d),16)+54);
      final wide=box.maxWidth>=1080 && box.maxWidth>=requiredWidth && MediaQuery.textScalerOf(context).scale(16)<=20;
      final showBrand=box.maxWidth>=600;
      return Row(children:[
        IconButton(tooltip:AppLocalizations.of(context).languageCode=='en'?'Open menu':'Ouvrir le menu',icon:const Icon(Icons.menu),onPressed:()=>Scaffold.of(context).openDrawer()),
        if(showBrand)TextButton(onPressed:()=>V2DraftScope.maybeOf(context)?.home(),child:const Text.rich(TextSpan(children:[
          TextSpan(text:'Elev’',style:TextStyle(color:Colors.white)),TextSpan(text:'Age',style:TextStyle(color:Color(0xFF4CAF50)))]),style:TextStyle(fontSize:24,fontWeight:FontWeight.bold))),
        if(wide)...[const Spacer(),for(final d in farmHorizontalNavigationOrder)if(visible(d))TextButton.icon(
          key:d==FarmDestination.production?const Key('topProductionTrackingButton'):ValueKey('navigation-${d.name}-horizontal'),
          style:TextButton.styleFrom(foregroundColor:Colors.white,padding:const EdgeInsets.symmetric(horizontal:12),textStyle:const TextStyle(fontFamily:'Roboto',fontSize:16,fontWeight:FontWeight.w600)),
          onPressed:actions[d],icon:Icon(farmDestinationIcons[d],size:22),label:Text(navigationLabel(context,d)))],
        const Spacer(),connection,
        IconButton(tooltip:AppLocalizations.of(context).languageCode=='en'?'Refresh':'Actualiser',onPressed:onRefresh,icon:const Icon(Icons.refresh)),
        const SizedBox(height:32,child:VerticalDivider(color:Colors.white70,width:12)),
        if(wide)TextButton.icon(key:const Key('topLogoutButton'),style:TextButton.styleFrom(foregroundColor:Colors.white),onPressed:onLogout,icon:const Icon(Icons.logout),label:const Text('Quitter'))
        else IconButton(key:const Key('topLogoutButton'),tooltip:'Quitter',onPressed:onLogout,icon:const Icon(Icons.logout)),
      ]);
    }));
}
