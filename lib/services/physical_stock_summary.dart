import 'package:timezone/timezone.dart' as tz;
import '../offline/feed_stock_projection.dart';

/// Presentation only: quantities remain derived from the existing stock projections.
Map<String,dynamic> feedSummary(Map data,{int? species,int? lot}) {
  BigInt confirmed=BigInt.zero,pending=BigInt.zero;final details=<Map<String,dynamic>>[];
  for(final raw in data['products'] as List? ?? const []) {
    BigInt c=BigInt.zero,p=BigInt.zero,shared=BigInt.zero,reserved=BigInt.zero;
    for(final pos in raw['positions'] as List) {
      if(species!=null && pos['species_id']!=species)continue;
      if(lot!=null && pos['lot_id']!=null && pos['lot_id']!=lot)continue;
      final q=feedMilli(pos['kg']);c+=q;p+=feedMilli(pos['pending_kg']??'0',signed:true);
      if(pos['lot_id']==null){shared+=q;}else{reserved+=q;}
    }
    confirmed+=c;pending+=p;
    final threshold=raw['alert_threshold']==null?null:feedMilli(raw['alert_threshold']);
    details.add({...raw,'confirmed':feedKg(c),'pending':feedKg(p),'estimated':feedKg(c+p),
      'shared':feedKg(shared),'reserved':feedKg(reserved),
      // A whole-product threshold cannot be compared to a filtered subset.
      'low':species==null && lot==null && threshold!=null && threshold>BigInt.zero && c<=threshold,
      'empty':c==BigInt.zero});
  }
  return {'confirmed':feedKg(confirmed),'pending':feedKg(pending),'estimated':feedKg(confirmed+pending),'details':details};
}
Map<String,dynamic> vaccineSummary(Map data,DateTime now,{int? species,int? lot,int? warningDays}) {
  final details=<Map<String,dynamic>>[];var physical=0,usable=0,estimated=0,expired=0,unusable=0,vials=0,soon=0;
  for(final product in data['products'] as List? ?? const []) {
    var pc=0,uc=0,ec=0,xc=0,ic=0,vc=0,sc=0;
    for(final vial in data['vials'] as List? ?? const []) {
      if(vial['product']!=product['id'] || (species!=null && vial['species']!=species) ||
        (lot!=null && vial['lot']!=null && vial['lot']!=lot))continue;
      final q=vial['confirmed_physical'] as int? ?? vial['physical'] as int;
      final until=DateTime.parse((vial['confirmed_usable_until']??vial['usable_until']) as String);
      final open=DateTime.tryParse('${vial.containsKey('confirmed_opened_at')?vial['confirmed_opened_at']:vial['opened_at']}');
      // usable_until uses the server expiry boundary and explicit opening duration.
      final allowed=now.isBefore(until) && (open==null || !now.isBefore(open));
      final u=allowed?q:0;
      final localOpen=DateTime.tryParse('${vial['opened_at']}');
      final localAllowed=now.isBefore(DateTime.parse(vial['usable_until'] as String)) && (localOpen==null || !now.isBefore(localOpen));
      final e=localAllowed?(vial['estimated_physical'] as int? ?? q):0;
      final expiry=DateTime.parse('${vial['expires_on']}T00:00:00');
      // Calendar expiry comparison is anchored to the server Europe/Paris date below.
      final serverDay=parisDay(now);final isExpired=serverDay.isAfter(expiry);
      pc+=q;uc+=u;ec+=e;
      if(isExpired){xc+=q;}else if(!allowed){ic+=q;}
      if(u>0){vc++;}
      if(q>0 && !isExpired && warningDays!=null && !expiry.isAfter(serverDay.add(Duration(days:warningDays))))sc++;
    }
    physical+=pc;usable+=uc;estimated+=ec;expired+=xc;unusable+=ic;vials+=vc;soon+=sc;
    final threshold=num.tryParse('${product['alert_threshold']}');
    details.add({...product,'physical':pc,'usable':uc,'estimated':ec,'expired':xc,'unusable':ic,'vials':vc,'soon':sc,
      'low':species==null && lot==null && threshold!=null && threshold>0 && uc<=threshold});
  }
  return {'physical':physical,'usable':usable,'estimated':estimated,'expired':expired,'unusable':unusable,'vials':vials,'soon':soon,'details':details};
}

DateTime parisDay(DateTime now) {final d=tz.TZDateTime.from(now,tz.getLocation('Europe/Paris'));return DateTime(d.year,d.month,d.day);}
