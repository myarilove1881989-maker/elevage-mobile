import 'dart:typed_data';
import 'package:app_elevage/screens/invoice_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'production_tracking_test.dart' show testApp;

class PreviewPrintingFake extends PrintingPlatform {
  Uint8List? previewBytes;
  Uint8List? printedBytes;
  Uint8List? sharedBytes;
  String? sharedName;

  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canPrint: true, canShare: true, canRaster: true);

  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    previewBytes = document;
    yield PdfRaster(1, 1, Uint8List.fromList([255, 255, 255, 255]));
  }

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    printedBytes = await onLayout(format);
    return true;
  }

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async {
    sharedBytes = bytes;
    sharedName = filename;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final language in ['fr', 'en']) {
    testWidgets(
      'Aperçu $language imprime et partage le même PDF sans régénération',
      (tester) async {
        final previous = PrintingPlatform.instance;
        final platform = PreviewPrintingFake();
        PrintingPlatform.instance = platform;
        addTearDown(() => PrintingPlatform.instance = previous);
        await tester.runAsync(() async {
          await tester.pumpWidget(
            testApp(
              InvoicePreviewScreen(
                sale: const {
                  'id': 42,
                  'date': '2026-10-06',
                  'produit_vendu': 'OEUFS',
                  'nombre_oeufs': 100,
                  'conditionnement': 'COMPOSE',
                  'quantite': 1,
                  'prix_unitaire': 100,
                  'montant_total': 100,
                  'montant_paye': 40,
                  'reste': 60,
                  'exploitation_nom': 'Élevage Œuf',
                  'lot_nom': 'Pondeuses',
                },
                customerName: 'Client Œuf',
                customerPhone: '0000000000',
                languageCode: language,
              ),
            ),
          );
          // Les assets et le codec image utilisent de vraies opérations asynchrones.
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            await tester.pump(const Duration(milliseconds: 100));
            if (platform.previewBytes != null &&
                find.byIcon(Icons.print).evaluate().isNotEmpty) {
              break;
            }
          }
          expect(platform.previewBytes, isNotNull);
          await tester.tap(find.byIcon(Icons.print));
          await tester.pump();
          await tester.tap(find.byIcon(Icons.share));
          await tester.pump();
        });
        expect(platform.printedBytes, platform.previewBytes);
        expect(platform.sharedBytes, platform.previewBytes);
        expect(platform.sharedName, endsWith('_${language.toUpperCase()}.pdf'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
