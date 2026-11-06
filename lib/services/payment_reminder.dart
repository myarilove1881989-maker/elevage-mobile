import 'app_settings.dart';

String paymentReminder({required String customer,required String description,required num total,
    required num paid,required num remaining,required String farm,AppSettings? settings}) {
  final app=settings??AppSettings.instance;
  if(remaining<=0)throw ArgumentError('Cette facture est entièrement réglée.');
  String money(num n)=>app.formatMoney(n,decimals:2);
  return 'Bonjour Monsieur/Madame $customer 😊,\n\n'
    'Nous espérons que vous allez bien !\n\n'
    'Nous nous permettons de revenir vers vous concernant votre achat de $description, '
    'd’un montant total de ${money(total)}.\n\n'
    'Total déjà payé : ${money(paid)}.\n\n'
    'Sauf erreur de notre part, un solde de ${money(remaining)} reste à régler.\n\n'
    'Nous souhaitions simplement vous faire ce petit rappel et restons à votre disposition '
    'si vous avez besoin d’informations complémentaires.\n\n'
    'Merci encore pour votre confiance et au plaisir de continuer à vous accompagner ! 🤝\n\n$farm';
}
