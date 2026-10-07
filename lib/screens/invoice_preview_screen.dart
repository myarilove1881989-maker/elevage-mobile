import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../l10n/app_localizations.dart';
import '../services/invoice_pdf_service.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> sale;
  final String customerName;
  final String customerPhone;
  final String languageCode;

  const InvoicePreviewScreen({
    super.key,
    required this.sale,
    required this.customerName,
    required this.customerPhone,
    required this.languageCode,
  });

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  late final Future<Uint8List> _document = InvoicePdfService.buildInvoice(
    sale: widget.sale,
    customerName: widget.customerName,
    customerPhone: widget.customerPhone,
    languageCode: widget.languageCode,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.languageCode == 'fr' ? 'Facture PDF' : 'PDF invoice'),
    ),
    body: FutureBuilder<Uint8List>(
      future: _document,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(context.tr('invoice_unavailable')),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return PdfPreview(
          build: (_) async => bytes,
          pdfFileName: InvoicePdfService.documentName(
            widget.sale,
            widget.languageCode,
          ),
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          allowPrinting: true,
          allowSharing: true,
          onError: (_, _) =>
              Center(child: Text(context.tr('invoice_unavailable'))),
          onPrintError: (_, _) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('invoice_unavailable'))),
          ),
        );
      },
    ),
  );
}
