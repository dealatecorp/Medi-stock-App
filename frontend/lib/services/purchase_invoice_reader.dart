import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// Reads a supplier invoice on this device and proposes a number only when a
/// labelled, unambiguous value is present. The caller must keep the field
/// editable: OCR and supplier layouts are not guaranteed to be accurate.
class PurchaseInvoiceReader {
  static const maxPdfPagesToInspect = 3;
  static Future<void>? _pdfInitialization;

  /// Supported input: PDF, JPEG and PNG files on Android/iOS.
  ///
  /// Returns null for a missing or conflicting labelled number. File, PDF and
  /// native OCR errors are left to the caller so they can show a manual-entry
  /// prompt instead of silently claiming an invoice number was detected.
  Future<String?> extractInvoiceNumber(String filePath) async {
    final extension = filePath.split('.').last.toLowerCase();
    if (extension == 'pdf') {
      return _readPdf(filePath);
    }
    if (const {'jpg', 'jpeg', 'png'}.contains(extension)) {
      return PurchaseInvoiceNumberParser.extract(await _readPhoto(filePath));
    }
    throw UnsupportedError('Unsupported invoice file type: .$extension');
  }

  Future<String> _readPhoto(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  Future<String?> _readPdf(String path) async {
    WidgetsFlutterBinding.ensureInitialized();
    await (_pdfInitialization ??= pdfrxFlutterInitialize());

    final document = await PdfDocument.openFile(path);
    try {
      final pages = document.pages.take(maxPdfPagesToInspect).toList();
      final text = <String>[];
      for (final page in pages) {
        text.add((await page.loadText())?.fullText ?? '');
      }
      // Image-only PDFs contain no selectable text. Render those pages locally
      // and run the same on-device recognizer used for photos.
      final ocrText = <String>[];
      for (var index = 0; index < pages.length; index++) {
        if (text[index].trim().isNotEmpty) continue;
        ocrText.add(await _readScannedPage(pages[index]));
      }
      return PurchaseInvoiceNumberParser.extract(
        [...text, ...ocrText].join('\n'),
      );
    } finally {
      await document.dispose();
    }
  }

  Future<String> _readScannedPage(PdfPage page) async {
    // Around 180 dpi, capped to keep high-resolution supplier PDFs bounded.
    const maxDimension = 2400.0;
    final scale = (maxDimension /
            (page.width > page.height ? page.width : page.height))
        .clamp(1.0, 2.5);
    final rendered = await page.render(
      width: (page.width * scale).round(),
      height: (page.height * scale).round(),
    );
    if (rendered == null) return '';

    File? temporaryFile;
    try {
      final bitmap = rendered.createImageNF();
      final png = image.encodePng(bitmap);
      final directory = await getTemporaryDirectory();
      temporaryFile = File(
        '${directory.path}${Platform.pathSeparator}'
        'medistock-invoice-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await temporaryFile.writeAsBytes(png, flush: true);
      return await _readPhoto(temporaryFile.path);
    } finally {
      rendered.dispose();
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }
}

/// Conservative, pure-Dart parser that never guesses from an unlabelled ID.
class PurchaseInvoiceNumberParser {
  PurchaseInvoiceNumberParser._();

  static final _label = RegExp(
    r'\b(?:tax\s+|purchase\s+)?(?:invoice|inv\.?|bill)\s*'
    r'(?:number|num\.?|no\.?|#)\s*[:#\-]?\s*(.*)$',
    caseSensitive: false,
  );
  static final _number = RegExp(r'^[A-Z0-9][A-Z0-9/_\-.]{1,39}',
      caseSensitive: false);
  static final _date = RegExp(
    r'^(?:\d{1,4}[-/.]\d{1,2}[-/.]\d{2,4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{2,4})$',
    caseSensitive: false,
  );

  static String? extract(String text) {
    final lines = text
        .replaceAll(RegExp(r'[\u2010-\u2015\u2212]'), '-')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .toList();
    final found = <String, String>{};
    for (var index = 0; index < lines.length; index++) {
      final match = _label.firstMatch(lines[index]);
      if (match == null) continue;
      var tail = match.group(1)!.trim();
      if (tail.isEmpty && index + 1 < lines.length) {
        tail = lines[index + 1];
      }
      final candidate = _number.firstMatch(tail)?.group(0);
      if (candidate == null) continue;
      final number = candidate.replaceFirst(RegExp(r'[.\-]+$'), '');
      if (number.length < 2 ||
          _date.hasMatch(number) ||
          const {'DATE', 'GST', 'GSTIN', 'TOTAL', 'AMOUNT', 'NUMBER', 'NO'}
              .contains(number.toUpperCase())) {
        continue;
      }
      found.putIfAbsent(number.toUpperCase(), () => number);
      if (found.length > 1) return null;
    }
    return found.isEmpty ? null : found.values.single;
  }
}
