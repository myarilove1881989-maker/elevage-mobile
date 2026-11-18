import 'permission_contract.dart';

/// Narrow only the personal HTTP presentation contract. Never use for signed
/// grants, tablet profiles or operation authorization. Unsupported vaccine
/// actions remain unavailable on Android119's unchanged offline catalogue.
PermissionContract androidOnlinePermissions(Map<String,dynamic> data,{
  required int userId,required int farmId,required String role,required int rightsVersion,
}) {
  return PermissionContract.decode(data,userId:userId,farmId:farmId,role:role,rightsVersion:rightsVersion,allowHttpV2:true);
}
