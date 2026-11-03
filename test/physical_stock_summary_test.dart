import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/services/physical_stock_summary.dart';
Map<String,dynamic> feedData()=>{'exploitation':1,'as_of':'2026-11-03T10:00:00Z','products':[
  {'id':'feed','name':'Croissance','archived':false,'alert_threshold':'450.000','positions':[
    {'species_id':4,'lot_id':null,'kg':'500.000','pending_kg':'-80.000'},
    {'species_id':4,'lot_id':10,'kg':'50.125','pending_kg':'0.000'},
    {'species_id':4,'lot_id':11,'kg':'60.000','pending_kg':'0.000'},
    {'species_id':5,'lot_id':null,'kg':'100.000','pending_kg':'0.000'}]}]};
Map<String,dynamic> vaccines()=>{'exploitation':1,'as_of':'2026-11-03T10:00:00Z','products':[
  {'id':'vac','name':'Vaccin test','archived':false,'alert_threshold':'150'}],'vials':[
  {'id':'a','product':'vac','species':4,'lot':null,'physical':20,'estimated_physical':15,'usable_until':'2026-11-04T23:00:00Z','expires_on':'2026-11-04','opened_at':null},
  {'id':'b','product':'vac','species':4,'lot':10,'physical':20,'usable_until':'2026-11-02T23:00:00Z','expires_on':'2026-11-02','opened_at':null},
  {'id':'c','product':'vac','species':4,'lot':null,'physical':5,'usable_until':'2026-11-03T09:00:00Z','expires_on':'2026-11-30','opened_at':'2026-11-03T08:00:00Z'}]};
void main(){
  setUpAll(tzdata.initializeTimeZones);
  test('feed filters shared plus only chosen reserved lot and exact decimals',(){final s=feedSummary(feedData(),species:4,lot:10);expect(s['confirmed'],'550.125');expect(s['pending'],'-80.000');expect(s['estimated'],'470.125');expect(s['details'][0]['shared'],'500.000');expect(s['details'][0]['reserved'],'50.125');});
  test('totals count shared once and filtered stock never compared to whole product threshold',(){final data=feedData();expect(feedSummary(data)['confirmed'],'710.125');data['products'][0]['alert_threshold']='800';expect(feedSummary(data)['details'][0]['low'],true);expect(feedSummary(data,species:4)['details'][0]['low'],false);});
  test('old snapshots missing thresholds remain readable without invented weak-stock threshold',(){final d=feedData();d['products'][0].remove('alert_threshold');expect(feedSummary(d)['details'][0]['low'],false);});
  test('expiry and explicit opened duration exclude present physical doses and pending remains estimate',(){final s=vaccineSummary(vaccines(),DateTime.utc(2026,11,3,10));expect(s['physical'],45);expect(s['usable'],20);expect(s['estimated'],15);expect(s['expired'],20);expect(s['unusable'],5);expect(s['vials'],1);expect(s['soon'],0);});
  test('near-expiry horizon must be explicitly set',(){expect(vaccineSummary(vaccines(),DateTime.utc(2026,11,3,10),warningDays:1)['soon'],1);});
  test('expiry recalculated across midnight Paris even on device in different timezone',(){final s=vaccineSummary(vaccines(),DateTime.utc(2026,11,4,23));expect(s['usable'],0);expect(s['vials'],0);expect(s['expired'],40);});
  test('a pending local opening expiry changes estimate without rewriting server-confirmed availability',(){final d=vaccines();d['vials'][0]['confirmed_usable_until']='2026-11-04T23:00:00Z';d['vials'][0]['confirmed_opened_at']=null;d['vials'][0]['usable_until']='2026-11-03T09:00:00Z';d['vials'][0]['opened_at']='2026-11-03T08:00:00Z';final s=vaccineSummary(d,DateTime.utc(2026,11,3,10));expect(s['usable'],20);expect(s['estimated'],0);});
  test('future opening is never usable',(){final d=vaccines();d['vials'][0]['opened_at']='2026-11-04T12:00:00Z';expect(vaccineSummary(d,DateTime.utc(2026,11,3,10))['usable'],0);});
  test('negative local estimate is retained as a discrepancy, not silently clamped',(){final d=feedData();d['products'][0]['positions'][0]['pending_kg']='-900';expect(feedSummary(d)['estimated'],'-189.875');});
}
