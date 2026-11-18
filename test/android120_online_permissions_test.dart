import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/services/android_online_permissions.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/user_administration_service.dart';
Map<String,dynamic> contract()=>{'version':2,'user':1,'exploitation':1,'role':'OWNER','rights_version':1,'permissions':[
 ...PermissionContract.catalogue.where((p)=>p!='agenda.progress' && !p.startsWith('vaccinations.')),
 'vaccinations.read','vaccinations.create','vaccinations.update','vaccinations.delete','vaccinations.loss']};
class OwnerCapabilities extends ApiService {
 @override Future<dynamic> get(String path)async=>path=='/memberships/'?[]:{'user':1,'exploitation':1,'role':'OWNER','membership':{'version':1},'user_administration_contract':1,'permission_contract':contract()};
}
void main(){
 test('current HTTP owner contract retains explicit supported vaccine rights',(){
   final rights=androidOnlinePermissions(contract(),userId:1,farmId:1,role:'OWNER',rightsVersion:1);
   expect(rights.allows('stocks.read'),true);expect(rights.allows('purchases.create'),true);expect(rights.allows('vaccinations.create'),true);
 });
 test('unknown rights, duplicate codes and cross-farm identities fail closed',(){
   for(final bad in [contract()..['exploitation']=2,contract()..['permissions']=['finance.read','unknown.write'],contract()..['permissions']=['finance.read','finance.read']]){
     expect(()=>androidOnlinePermissions(bad,userId:1,farmId:1,role:'OWNER',rightsVersion:1),throwsStateError);
   }
 });
 test('extended HTTP catalogue recognizes explicit vaccine rights without adding absent rights',(){
   final rights=PermissionContract.decode(contract(),userId:1,farmId:1,role:'OWNER',rightsVersion:1,allowHttpV2:true);
   expect(rights.allows('vaccinations.create'),isTrue);
   final absent=contract()..['permissions']=['finance.read'];
   expect(PermissionContract.decode(absent,userId:1,farmId:1,role:'OWNER',rightsVersion:1,allowHttpV2:true).allows('vaccinations.create'),isFalse);
 });
 test('owner administration reads the current HTTP catalogue with its existing guard',()async{
   ApiService.token='synthetic-owner';final api=OwnerCapabilities();final service=UserAdministrationService(api);
   try{await service.initialize();expect(await service.list(),isEmpty);}finally{api.close();ApiService.token=null;}
 });
}
