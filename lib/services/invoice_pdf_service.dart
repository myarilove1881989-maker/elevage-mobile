import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class InvoicePdfService {
  static const _navy = PdfColor.fromInt(0xFF073B5C);
  static const _green = PdfColor.fromInt(0xFF178A5A);
  static const _gold = PdfColor.fromInt(0xFFD49A22);
  static const _ink = PdfColor.fromInt(0xFF173042);
  static const _muted = PdfColor.fromInt(0xFF667985);
  static const _line = PdfColor.fromInt(0xFFD9E3E7);
  static const _paleGreen = PdfColor.fromInt(0xFFEEF6F2);
  static const _paleGold = PdfColor.fromInt(0xFFFFF6DF);

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _money(dynamic value) {
    return '${NumberFormat('#,##0', 'fr_FR').format(_number(value))} FCFA';
  }

  static String _safe(dynamic value, [String fallback = '-']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static Future<void> openInvoice({
    required Map<String, dynamic> sale,
    required String customerName,
    required String customerPhone,
    required String languageCode,
  }) async {
    final isFr = languageCode == 'fr';
    final isPaid = _number(sale['reste']) <= 0;
    final invoicePrefix = isFr ? 'FAC' : 'INV';
    final invoiceNumber = '$invoicePrefix-${DateTime.now().year}-${sale['id'].toString().padLeft(5, '0')}';
    final farmName = _safe(sale['exploitation_nom'], isFr ? 'Mon exploitation' : 'My farm');
    final farmId = _safe(sale['exploitation_id']);
    final total = _number(sale['montant_total']);
    final paid = _number(sale['montant_paye']);
    final balance = _number(sale['reste']);
    final statusColor = isPaid ? _green : _gold;
    final paleColor = isPaid ? _paleGreen : _paleGold;
    final pdf = pw.Document(
      title: '$invoiceNumber - $farmName',
      author: "Elev'Age",
    );

    pw.Widget infoCell(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _muted)),
              pw.SizedBox(height: 3),
              pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
            ],
          ),
        );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(44, 42, 44, 38),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(height: 6, color: _navy),
            pw.SizedBox(height: 24),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(text: "Elev'", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: _navy)),
                          pw.TextSpan(text: 'Age', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: _gold)),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 7),
                    pw.Text('${isFr ? 'EXPLOITATION' : 'FARM'} : $farmName', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green)),
                    pw.Text('${isFr ? 'Identifiant exploitation' : 'Farm identifier'} : $farmId', style: const pw.TextStyle(fontSize: 8, color: _muted)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(isFr ? 'FACTURE / REÇU' : 'INVOICE / RECEIPT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _navy)),
                    pw.SizedBox(height: 5),
                    pw.Text(invoiceNumber, style: const pw.TextStyle(fontSize: 9, color: _muted)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 26),
            pw.Container(
              color: statusColor,
              padding: const pw.EdgeInsets.symmetric(vertical: 9),
              child: pw.Text(
                isFr ? (isPaid ? 'PAYÉE' : 'PAIEMENT PARTIEL') : (isPaid ? 'PAID IN FULL' : 'PARTIALLY PAID'),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(color: PdfColors.white, fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Container(
              color: paleColor,
              padding: const pw.EdgeInsets.symmetric(vertical: 7),
              child: pw.Text('${isFr ? 'Montant payé' : 'Amount paid'} : ${_money(paid)}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
            ),
            pw.SizedBox(height: 22),
            pw.Table(
              border: pw.TableBorder.all(color: _line, width: .7),
              columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1)},
              children: [
                pw.TableRow(children: [
                  infoCell(isFr ? 'CLIENT' : 'CUSTOMER', customerName),
                  infoCell(isFr ? 'TELEPHONE' : 'PHONE', _safe(customerPhone)),
                  infoCell(isFr ? 'DATE' : 'DATE', _safe(sale['date'])),
                ]),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Table(
              border: pw.TableBorder.all(color: _line, width: .7),
              columnWidths: const {0: pw.FlexColumnWidth(1.35), 1: pw.FlexColumnWidth(1.45), 2: pw.FlexColumnWidth(.55), 3: pw.FlexColumnWidth(.9), 4: pw.FlexColumnWidth(1)},
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _navy),
                  children: (isFr
                          ? ['DÉSIGNATION', 'LOT', 'QTÉ', 'PRIX UNIT.', 'TOTAL']
                          : ['DESCRIPTION', 'BATCH', 'QTY', 'UNIT PRICE', 'TOTAL'])
                      .map((label) => pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(label, style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold))))
                      .toList(),
                ),
                pw.TableRow(children: [
                  _tableValue(_safe(sale['espece'])),
                  _tableValue(_safe(sale['lot_nom'])),
                  _tableValue(_safe(sale['quantite'])),
                  _tableValue(_money(sale['prix_unitaire'])),
                  _tableValue(_money(total)),
                ]),
              ],
            ),
            pw.SizedBox(height: 22),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 245,
                child: pw.Column(children: [
                  _totalLine(isFr ? 'TOTAL FACTURE' : 'INVOICE TOTAL', _money(total)),
                  _totalLine(isFr ? 'MONTANT PAYÉ' : 'AMOUNT PAID', _money(paid)),
                  pw.Container(
                    color: paleColor,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text(isFr ? 'RESTE À PAYER' : 'BALANCE DUE', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
                      pw.Text(_money(balance), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                    ]),
                  ),
                ]),
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              decoration: pw.BoxDecoration(color: paleColor, border: pw.Border.all(color: statusColor, width: .8)),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Text(
                isFr
                    ? (isPaid ? 'Cette facture est intégralement réglée. Aucun solde ne reste dû.' : 'Paiement partiel enregistré. Le solde indiqué reste à régler.')
                    : (isPaid ? 'This invoice has been paid in full. No balance remains due.' : 'Partial payment recorded. The balance shown remains due.'),
                style: const pw.TextStyle(fontSize: 9, color: _ink),
              ),
            ),
            pw.Spacer(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(farmName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.Text(customerName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
            ]),
            pw.SizedBox(height: 18),
            pw.Divider(color: _gold, thickness: 3),
            pw.Text(isFr ? "Document généré par Elev'Age." : "Generated by Elev'Age.", textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7, color: _muted)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      name: '${invoiceNumber}_${languageCode.toUpperCase()}.pdf',
      onLayout: (_) async => pdf.save(),
    );
  }

  static pw.Widget _tableValue(String value) => pw.Padding(
        padding: const pw.EdgeInsets.all(7),
        child: pw.Text(value, style: const pw.TextStyle(fontSize: 8, color: _ink)),
      );

  static pw.Widget _totalLine(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
        ]),
      );
}
