import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

// How a business rejection of a vote is written, on the wire (the body of a
// 422) and in the outbox (the reason a vote was rejected). One description for
// both, so that what the server says and what the device remembers cannot
// drift apart.

const String _rejectionReasonWire = 'RejectionReasonWire';
const String _invalidCode = 'not a rejection code';
const String _invalidField = 'not a valid field';
const String _codeKey = 'code';
const String _resolutionIdKey = 'resolutionId';
const String _sourceKey = 'source';
const String _attemptsKey = 'attempts';

/// A rejection of a vote as it is written: a `code` and the fields of that
/// code.
@immutable
sealed class RejectionReasonWire {
  const new();

  /// The JSON object of this rejection.
  Map<String, Object?> toJson();
}

/// A [VotingError] as it is written.
@immutable
final class VotingErrorWire extends RejectionReasonWire {
  /// Creates the wire form of a voting error. `resolutionId` goes with
  /// `resolutionNotFound` and `source` with `alreadyVoted`.
  const new({required this.code, this.resolutionId, this.source});

  /// Which voting error it is.
  final VotingErrorCode code;

  /// The resolution that was not found.
  final String? resolutionId;

  /// Where the earlier vote is.
  final AlreadyVotedSource? source;

  @override
  Map<String, Object?> toJson() => {
    _codeKey: code.value,
    if (resolutionId != null) _resolutionIdKey: resolutionId,
    if (source != null) _sourceKey: source!.value,
  };

  @override
  bool operator ==(Object other) =>
      other is VotingErrorWire &&
      other.code == code &&
      other.resolutionId == resolutionId &&
      other.source == source;

  @override
  int get hashCode => Object.hash(code, resolutionId, source);

  @override
  String toString() => 'VotingErrorWire(${code.value})';
}

/// The giving up of a vote after its attempts, as it is written.
@immutable
final class UndeliverableWire extends RejectionReasonWire {
  /// Creates the wire form of a vote given up after [attempts].
  const new({required this.attempts});

  /// How many times delivery was tried.
  final int attempts;

  @override
  Map<String, Object?> toJson() => {
    _codeKey: VoteDeliveryErrorCode.undeliverable.value,
    _attemptsKey: attempts,
  };

  @override
  bool operator ==(Object other) =>
      other is UndeliverableWire && other.attempts == attempts;

  @override
  int get hashCode => attempts.hashCode;

  @override
  String toString() => 'UndeliverableWire($attempts)';
}

CheckedFromJsonException _flaw(
  Map<String, dynamic> json,
  String? key,
  String message,
) => CheckedFromJsonException(json, key, _rejectionReasonWire, message);

String _stringField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw _flaw(json, key, _invalidField);
  }
  return value;
}

VotingErrorWire _votingErrorOf(
  Map<String, dynamic> json,
  VotingErrorCode code,
) => switch (code) {
  VotingErrorCode.resolutionNotFound => VotingErrorWire(
    code: code,
    resolutionId: _stringField(json, _resolutionIdKey),
  ),
  VotingErrorCode.alreadyVoted => VotingErrorWire(
    code: code,
    source:
        findConstant(
          AlreadyVotedSource.values,
          _stringField(json, _sourceKey),
        ) ??
        (throw _flaw(json, _sourceKey, _invalidField)),
  ),
  VotingErrorCode.notAParticipant ||
  VotingErrorCode.noVotingRights ||
  VotingErrorCode.resolutionClosed ||
  VotingErrorCode.votingWindowOver => VotingErrorWire(code: code),
};

/// Reads a voting error, or throws a `CheckedFromJsonException` at the field
/// that is missing, has the wrong type or names a code that is not one. Fields
/// it does not know are ignored. The giving up of a vote is not a voting error.
VotingErrorWire votingErrorWireFromJson(Map<String, dynamic> json) {
  final code = findConstant(
    VotingErrorCode.values,
    _stringField(json, _codeKey),
  );
  if (code == null) {
    throw _flaw(json, _codeKey, _invalidCode);
  }
  return _votingErrorOf(json, code);
}

/// Reads a rejection reason: a voting error, or the vote being given up after
/// its attempts. Throws like [votingErrorWireFromJson].
RejectionReasonWire rejectionReasonWireFromJson(Map<String, dynamic> json) {
  final code = _stringField(json, _codeKey);
  if (code != VoteDeliveryErrorCode.undeliverable.value) {
    return votingErrorWireFromJson(json);
  }
  final attempts = json[_attemptsKey];
  if (attempts is! num || attempts != attempts.truncate() || attempts < 0) {
    throw _flaw(json, _attemptsKey, _invalidField);
  }
  return UndeliverableWire(attempts: attempts.toInt());
}

/// The voting error a payload describes, through the factories of the domain.
Result<VotingError, ValidationError> toVotingError(VotingErrorWire wire) =>
    switch (wire.code) {
      VotingErrorCode.resolutionNotFound => map(
        parseResolutionId(wire.resolutionId!),
        (resolutionId) => ResolutionNotFoundError(resolutionId: resolutionId),
      ),
      VotingErrorCode.notAParticipant => ok(const NotAParticipantError()),
      VotingErrorCode.noVotingRights => ok(const NoVotingRightsError()),
      VotingErrorCode.resolutionClosed => ok(const ResolutionClosedError()),
      VotingErrorCode.votingWindowOver => ok(const VotingWindowOverError()),
      VotingErrorCode.alreadyVoted => ok(
        AlreadyVotedError(source: wire.source!),
      ),
    };

/// The reason a rejected vote was kept for, as read back.
Result<RejectionReason, ValidationError> toRejectionReason(
  RejectionReasonWire wire,
) => switch (wire) {
  UndeliverableWire(:final attempts) => ok(voteUndeliverable(attempts)),
  VotingErrorWire() => toVotingError(wire),
};

/// A voting error, written. A plain copy: the wire format is the shape of the
/// error itself.
VotingErrorWire toVotingErrorWire(VotingError error) => switch (error) {
  ResolutionNotFoundError(:final resolutionId) => VotingErrorWire(
    code: VotingErrorCode.resolutionNotFound,
    resolutionId: resolutionId,
  ),
  NotAParticipantError() => const VotingErrorWire(
    code: VotingErrorCode.notAParticipant,
  ),
  NoVotingRightsError() => const VotingErrorWire(
    code: VotingErrorCode.noVotingRights,
  ),
  ResolutionClosedError() => const VotingErrorWire(
    code: VotingErrorCode.resolutionClosed,
  ),
  VotingWindowOverError() => const VotingErrorWire(
    code: VotingErrorCode.votingWindowOver,
  ),
  AlreadyVotedError(:final source) => VotingErrorWire(
    code: VotingErrorCode.alreadyVoted,
    source: source,
  ),
};

/// A rejection reason, written.
RejectionReasonWire toRejectionReasonWire(RejectionReason reason) =>
    switch (reason) {
      VoteUndeliverableError(:final attempts) => UndeliverableWire(
        attempts: attempts,
      ),
      VotingError() => toVotingErrorWire(reason),
    };
