import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// The SHA-256 digest of the UTF-8 form of [text], as 64 lower case
/// hexadecimal digits. It names files: the name of a downloaded document is
/// the digest of who it was downloaded for, which document, and which version,
/// so that two different triples can never share a file, whatever characters
/// their parts contain, and the name is short, safe in every file system and
/// carries nothing of the identifiers.
///
/// A lone surrogate, which has no UTF-8 form, is written as U+FFFD. It is for
/// short texts (identifiers).
String sha256Hex(String text) =>
    crypto.sha256.convert(utf8.encode(text)).toString();
