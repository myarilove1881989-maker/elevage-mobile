import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:app_elevage/services/invoice_pdf_service.dart';

class _CapturePrinting extends PrintingPlatform {
  Uint8List? bytes;
  String? documentName;

  @override
  Future<bool> layoutPdf(Printer? printer, LayoutCallback onLayout, String name,
      PdfPageFormat format, bool dynamicLayout, bool usePrinterSettings,
      OutputType outputType, bool forceCustomPrintPaper) async {
    bytes = await onLayout(format);
    documentName = name;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (product, language, balance) in [
    ('ANIMAUX', 'fr', 0),
    ('ANIMAUX', 'en', 30),
    ('OEUFS', 'fr', 60),
    ('OEUFS', 'en', 0),
  ]) {
    test('$product invoice in $language renders accents without missing glyphs',
        () async {
      final previous = PrintingPlatform.instance;
      final capture = _CapturePrinting();
      PrintingPlatform.instance = capture;
      addTearDown(() => PrintingPlatform.instance = previous);
      final messages = <String>[];
      await runZoned(
        () => InvoicePdfService.openInvoice(
          sale: {
            'id': 42, 'date': '2026-10-05', 'produit_vendu': product,
            'espece': 'Poule', 'lot_nom': 'Lot œufs et élevage',
            'quantite': product == 'OEUFS' ? 1 : 5,
            'prix_unitaire': product == 'OEUFS' ? 100 : 20,
            'montant_total': 100, 'montant_paye': 100 - balance,
            'reste': balance, 'nombre_oeufs': 100,
            'conditionnement': 'COMPOSE',
            'exploitation_nom': 'Élevage de Frédéric', 'exploitation_id': 42,
          },
          customerName: 'Client Œuf Frédéric',
          customerPhone: '0000000000', languageCode: language,
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, message) => messages.add(message),
        ),
      );
      expect(capture.bytes, isNotNull);
      expect(ascii.decode(capture.bytes!.take(4).toList()), '%PDF');
      expect(capture.bytes!.length, greaterThan(1000));
      expect(capture.documentName,
          startsWith(language == 'fr' ? 'FAC-' : 'INV-'));
      expect(messages.where((m) => m.contains('Unable to find a font') ||
          m.contains('has no Unicode support')), isEmpty);
    });
  }
}
