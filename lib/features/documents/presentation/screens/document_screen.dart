import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:flutter/widgets.dart';

/// The document viewer (docs/spec/screens.md "Document").
///
/// A placeholder until the documents agent writes the screen: the router mounts
/// this class with this constructor, so the file is replaced in place.
/// [documentId] is the raw path parameter: the screen parses it with
/// `parseDocumentId` and shows "not found" for one it refuses.
class DocumentScreen extends StatelessWidget {
  /// Creates the screen for the document with the raw id [documentId].
  const new({required this.documentId, super.key});

  /// The raw `documentId` path parameter.
  final String documentId;

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key(DocumentsTestIds.documentScreen));
}
