import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/domain/value_objects/email_address.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'watermark.freezed.dart';

/// What every document shows on every page to identify who is reading it.
///
/// The domain guarantees the content: the full name and the email of the
/// signed-in user, taken from validated data (never blank, a well-formed
/// email), and the instant at which the document was opened. It deliberately
/// leaves everything visual to the presentation: how the instant is formatted
/// (language, time zone, date style), and the layout (text, tiling, angle,
/// opacity).
@freezed
abstract class Watermark with _$Watermark {
  /// Creates a watermark from its parts. Use [createWatermark] from the user
  /// who reads.
  const factory({
    required String fullName,
    required EmailAddress email,
    required Instant viewedAt,
  }) = _Watermark;
}

/// Builds the watermark of the [reader], the signed-in user who opens the
/// document. The documents read the user of `auth` as it is: a feature may
/// depend on the domain of the one it serves.
Watermark createWatermark(User reader, Instant viewedAt) => Watermark(
  fullName: reader.fullName,
  email: reader.email,
  viewedAt: viewedAt,
);
