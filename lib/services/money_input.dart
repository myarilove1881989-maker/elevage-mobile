import 'package:flutter/services.dart';
import 'app_settings.dart';

/// Display is localised; transport stays an exact decimal string, never rounded.
class MoneyInput {
  static bool get english => AppSettings.instance.languageCode == 'en';
  static String canonical(String value, {bool? en}) {
    var raw=value.replaceAll(RegExp(r'[\s\u00a0\u202f]'),'');
    if(en ?? english) {
      raw=raw.replaceAll(',','');
    } else {
      raw=raw.replaceAll(',','.');
    }
    return raw;
  }
  static String display(String decimal,{bool? en}) {
    if(decimal.isEmpty)return '';
    final parts=decimal.split('.');
    final grouped=parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>(en??english)?',':'\u202f');
    return '$grouped${parts.length==2?'${(en??english)?'.':','}${parts[1]}':''}';
  }
  static num? number(String value)=>num.tryParse(canonical(value));
}

class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue,TextEditingValue newValue) {
    if(!newValue.composing.isCollapsed)return newValue;
    final raw=MoneyInput.canonical(newValue.text);
    if(!RegExp(r'^\d*(\.\d*)?$').hasMatch(raw))return oldValue;
    final text=MoneyInput.display(raw);
    final before=MoneyInput.canonical(newValue.text.substring(0,newValue.selection.extentOffset.clamp(0,newValue.text.length)));
    int offset=0,seen=0;
    while(offset<text.length && seen<before.length) {
      if(!RegExp(r'[\s\u00a0\u202f,]').hasMatch(text[offset]) || (!MoneyInput.english && text[offset]==','))seen++;
      offset++;
    }
    return TextEditingValue(text:text,selection:TextSelection.collapsed(offset:offset));
  }
}
