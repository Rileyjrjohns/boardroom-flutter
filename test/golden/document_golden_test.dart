import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/documents/presentation/screens/document_screen.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/builders/builders.dart';
import '../support/presentation/test_app.dart';
import 'support/golden_screen.dart';
import 'support/pdf_page_stand_in.dart';

// The document screen in its main states, in English and in French, at the size
// of a phone: a confidential document with its protected badge, the watermark
// over the page and the page indicator, the same document opened from the copy
// saved on the device while offline, and the error of a document that cannot be
// opened. The PDF view is a stand-in that draws a page.

final Document _report = aConfidentialDocument(
  id: aDocumentId('report'),
  title: 'Remuneration report',
  pageCount: 12,
);

final DocumentLocation _location = aDocumentLocation(
  'file:///documents/report.pdf',
);

Widget _screen() => DocumentScreen(documentId: _report.id);

void _serve(TestApp app) {
  app.fakes.documents.addDocument(_report, _location);
}

Future<void> _saveThenGoOffline(TestApp app) async {
  app.fakes.auth.session = aSession(expiresAt: at(30 * millisPerDay));
  await app.fakes.documentCache.save(
    aUserId(),
    ViewableDocument(document: _report, location: _location),
    now,
  );
  app.fakes.clock.advance(millisPerDay ~/ 2);
  app.fakes.network.goOffline();
}

/// A document the server refuses to this reader.
void _forbid(TestApp app) {
  app.fakes.documents
    ..addDocument(_report, _location)
    ..failure = forbidden();
}

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;
    screenGoldenTest(
      'the document screen in $code',
      fileName: 'document_$code',
      scenarios: [
        goldenScenario(
          name: 'loaded, protected',
          locale: locale,
          screen: _screen,
          prepare: _serve,
          overrides: [pdfPageStandInOverride],
        ),
        goldenScenario(
          name: 'saved copy, offline',
          locale: locale,
          screen: _screen,
          prepare: _saveThenGoOffline,
          deviceOffline: true,
          overrides: [pdfPageStandInOverride],
        ),
        goldenScenario(
          name: 'error',
          locale: locale,
          screen: _screen,
          prepare: _forbid,
          overrides: [pdfPageStandInOverride],
        ),
      ],
    );
  }
}
