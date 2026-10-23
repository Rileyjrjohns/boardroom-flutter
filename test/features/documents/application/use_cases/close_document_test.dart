import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/use_cases/close_document.dart';
import 'package:boardroom/features/documents/application/use_cases/open_document.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:test/test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/fakes/create_fakes.dart';

final Document _a = aConfidentialDocument(id: aDocumentId('document-A'));
final Document _b = aConfidentialDocument(id: aDocumentId('document-B'));

({Fakes fakes, OpenDocument open, CloseDocument close}) _setup() {
  final fakes = createFakes();
  fakes.documents.addDocument(_a, aDocumentLocation('file:///private/a.pdf'));
  fakes.documents.addDocument(_b, aDocumentLocation('file:///private/b.pdf'));
  return (fakes: fakes, open: OpenDocument(fakes), close: CloseDocument(fakes));
}

void main() {
  group('CloseDocument', () {
    test('turns the screen protection off when the document was the only one '
        'open', () async {
      final (:fakes, :open, :close) = _setup();
      await open.execute(documentId: _a.id);

      expect(await close.execute(documentId: _a.id), equals(ok<void>(null)));
      expect(fakes.screenProtection.enabled, isFalse);
    });

    test('keeps the screen protected while another confidential document is '
        'still open', () async {
      final (:fakes, :open, :close) = _setup();
      await open.execute(documentId: _a.id);
      await open.execute(documentId: _b.id);

      await close.execute(documentId: _b.id);
      expect(fakes.screenProtection.enabled, isTrue);

      await close.execute(documentId: _a.id);
      expect(fakes.screenProtection.enabled, isFalse);
    });

    test('ignores a document that is not open: the protection is left as it '
        'is', () async {
      final (:fakes, :open, :close) = _setup();
      await open.execute(documentId: _a.id);

      expect(await close.execute(documentId: _b.id), equals(ok<void>(null)));
      expect(fakes.screenProtection.enabled, isTrue);
      expect(fakes.screenProtection.disableCalls, equals(0));
    });

    test('succeeds when nothing is open', () async {
      final (:fakes, :open, :close) = _setup();

      expect(await close.execute(documentId: _a.id), equals(ok<void>(null)));
      expect(fakes.screenProtection.disableCalls, equals(0));
    });

    test('returns the failure of the protection, and a second call '
        'retries', () async {
      final (:fakes, :open, :close) = _setup();
      await open.execute(documentId: _a.id);
      fakes.screenProtection.disableFailure = screenProtectionFailed();

      expect(
        await close.execute(documentId: _a.id),
        equals(err(screenProtectionFailed())),
      );

      fakes.screenProtection.disableFailure = null;
      expect(await close.execute(documentId: _a.id), equals(ok<void>(null)));
      expect(fakes.screenProtection.enabled, isFalse);
    });
  });
}
