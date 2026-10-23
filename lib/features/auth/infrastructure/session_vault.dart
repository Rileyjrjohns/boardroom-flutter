import 'dart:async';
import 'dart:convert';

import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/infrastructure/http/dto/wire.dart';
import 'package:boardroom/core/infrastructure/http/http_client.dart';
import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';
import 'package:boardroom/core/infrastructure/shared/attempt.dart';
import 'package:boardroom/core/infrastructure/shared/serial_queue.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:boardroom/features/auth/domain/value_objects/email_address.dart';
import 'package:boardroom/features/auth/infrastructure/dto/session_dto.dart';
import 'package:json_annotation/json_annotation.dart';

part 'session_vault.g.dart';

/// How long the keychain may take to answer before the call is a storage
/// failure.
const int defaultStorageTimeoutMillis = 10000;

/// What the session is called in the logs.
const String _sessionResource = 'session';

/// The `cause` of the error an item that no longer reads back is reported with.
const String _unreadableCause = 'session unreadable';

const String _invalidToken = 'not a token';

String _readStoredToken(Object raw) {
  if (raw is! String || raw.isEmpty) {
    throw const FormatException(_invalidToken);
  }
  return raw;
}

/// The session and its token as they are kept: one item, so that a replacement
/// is one write.
@JsonSerializable(checked: true, explicitToJson: true)
final class StoredSessionWire {
  /// Creates the stored form of a session.
  const new({required this.token, required this.user, required this.expiresAt});

  /// Reads the stored form of a session, or throws a
  /// `CheckedFromJsonException` at the first field that is missing or has the
  /// wrong type.
  factory fromJson(Map<String, dynamic> json) =>
      _$StoredSessionWireFromJson(json);

  /// The bearer token.
  @JsonKey(fromJson: _readStoredToken)
  final String token;

  /// The signed-in user.
  final UserWire user;

  /// When the session ends, in milliseconds since the epoch.
  final num expiresAt;

  /// The JSON object of this session.
  Map<String, dynamic> toJson() => _$StoredSessionWireToJson(this);

  // The token is a secret: it never appears in a log.
  @override
  String toString() => 'StoredSessionWire(user: ${user.id})';
}

final class _Held {
  const new({required this.session, required this.token});

  final Session session;
  final String token;
}

/// The session of the signed-in user and the token that proves it, kept in the
/// secure storage of the device and read from memory once it has been loaded.
/// It
/// is what `HttpAuthSession` writes and what the HTTP client reads the token
/// from, when it creates a request.
///
/// - One item holds the session and the token, so replacing it is one write:
///   there is no instant at which the storage holds the token of a user and the
///   session of another, or none while a sign-in succeeds. The memory follows
///   the storage: it changes only once the write succeeded, so a write that
///   fails leaves the session as it was.
/// - Every operation goes through one queue, so that the order in which
///   sign-ins and sign-outs were asked is the order they happen in, and the
///   memory cannot end up with a session the storage does not hold.
/// - A write the vault gave up on, because the keychain took too long, can
/// still
///   land later, after the operations that were asked for since. When it does,
///   the vault puts the storage back in the state of its memory (through the
///   same queue, so after those operations): the later operation always wins,
///   and a session that was signed out is not brought back. That correction is
///   best effort and is not itself waited for a second time.
/// - A stored item that no longer reads back (the format changed, the storage
///   was tampered with) is treated as nobody being signed in: it is captured by
///   the monitoring, without its content, and deleted.
/// - Signing out empties the memory first, then the storage: whatever happens
/// to
///   the storage, the token is no longer used. A storage that cannot forget
///   reports it, and signing out can be tried again.
final class SessionVault implements BearerTokenSource {
  /// Creates a vault over `storage`. `timeoutMillis` defaults to
  /// [defaultStorageTimeoutMillis].
  new({
    required this._storage,
    required this._monitoring,
    int timeoutMillis = defaultStorageTimeoutMillis,
  }) : _timeout = timeoutMillis;

  final SecureStorage _storage;
  final Monitoring _monitoring;
  final int _timeout;

  _Held? _held;
  bool _loaded = false;
  final SerialQueue _serial = createSerialQueue();

  /// The session, or `null` when nobody is signed in. It is returned as stored,
  /// expired or not.
  Future<Result<Session?, StorageReadFailedError>> session() =>
      _serial(() async {
        final loaded = await _load();
        switch (loaded) {
          case Ok():
            return ok(_held?.session);
          case Err(:final error):
            return err(error);
        }
      });

  /// The token, with the user it was given to: what the HTTP client needs to
  /// send a request.
  @override
  Future<Result<BearerToken?, StorageReadFailedError>> token() =>
      _serial(() async {
        final loaded = await _load();
        if (loaded case Err(:final error)) {
          return err(error);
        }
        final held = _held;
        return ok(
          held == null
              ? null
              : BearerToken(token: held.token, userId: held.session.user.id),
        );
      });

  /// Stores the session and its token in place of any other. Nothing changes if
  /// the write fails.
  Future<Result<void, StorageWriteFailedError>> replace(SignedIn signedIn) =>
      _serial(() async {
        final SignedIn(:session, :token) = signedIn;
        final written = await _write(
          () => _storage.set(
            SecureStorageKey.session.value,
            _serialise(session, token),
          ),
        );
        if (written case Err(:final error)) {
          return err(storageWriteFailed(error.cause));
        }
        _held = _Held(session: session, token: token);
        _loaded = true;
        return ok<void>(null);
      });

  /// Forgets the session and its token. Succeeds when there was none.
  Future<Result<void, StorageWriteFailedError>> clear() => _serial(() async {
    _held = null;
    _loaded = true;
    final removed = await _write(
      () => _storage.remove(SecureStorageKey.session.value),
    );
    switch (removed) {
      case Ok():
        return ok<void>(null);
      case Err(:final error):
        return err(storageWriteFailed(error.cause));
    }
  });

  /// A change of the storage, bounded in time. When it did not settle in time,
  /// the storage is put back in the state of the memory once the call settles,
  /// whichever way it ends.
  Future<Result<void, AttemptFailure>> _write(
    Future<void> Function() change,
  ) async {
    Future<void>? call;
    final written = await attempt(() {
      final started = change();
      call = started;
      return started;
    }, _timeout);
    final pending = call;
    if (written case Err(:final error)
        when error.kind == AttemptFailureKind.timedOut && pending != null) {
      void correct() => unawaited(_serial(_matchStorageToMemory));
      unawaited(
        pending.then<void>((_) => correct(), onError: (Object _) => correct()),
      );
    }
    return written;
  }

  /// Makes the storage hold what the memory holds, after a call that landed
  /// late.
  Future<void> _matchStorageToMemory() async {
    if (!_loaded) {
      return;
    }
    final held = _held;
    await attempt(
      () => held == null
          ? _storage.remove(SecureStorageKey.session.value)
          : _storage.set(
              SecureStorageKey.session.value,
              _serialise(held.session, held.token),
            ),
      _timeout,
    );
  }

  /// Reads the storage the first time (and again after a read that failed).
  Future<Result<void, StorageReadFailedError>> _load() async {
    if (_loaded) {
      return ok<void>(null);
    }
    final read = await attempt(
      () => _storage.get(SecureStorageKey.session.value),
      _timeout,
    );
    switch (read) {
      case Err(:final error):
        return err(storageReadFailed(error.cause));
      case Ok(:final value):
        _held = value == null ? null : await _restore(value);
        _loaded = true;
        return ok<void>(null);
    }
  }

  /// The session an item holds, or nothing and the item dropped when it no
  /// longer reads back.
  Future<_Held?> _restore(String raw) async {
    final restored = _deserialise(raw);
    if (restored != null) {
      return restored;
    }

    _monitoring.captureError(
      MonitoringEvent.storedRowDiscarded,
      storageReadFailed(_unreadableCause),
      {LogAttribute.resource: _sessionResource},
    );
    // Best effort: the item is not used either way.
    await attempt(
      () => _storage.remove(SecureStorageKey.session.value),
      _timeout,
    );
    return null;
  }
}

String _serialise(Session session, String token) => jsonEncode(
  StoredSessionWire(
    token: token,
    user: UserWire(
      id: session.user.id,
      fullName: session.user.fullName,
      email: session.user.email,
    ),
    expiresAt: session.expiresAt,
  ).toJson(),
);

/// The session and the token an item holds, or `null` when it no longer reads
/// back.
_Held? _deserialise(String raw) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  final StoredSessionWire stored;
  switch (decodeWire(json, StoredSessionWire.fromJson)) {
    case Ok(:final value):
      stored = value;
    case Err():
      return null;
  }

  final StoredSessionWire(:token, :user, :expiresAt) = stored;
  final restored = andThen(
    parseUserId(user.id),
    (id) => andThen(
      parseEmailAddress(user.email),
      (email) => andThen(
        createUser(id: id, fullName: user.fullName, email: email),
        (valid) => andThen(
          parseInstant(expiresAt),
          (instant) => ok(
            _Held(
              token: token,
              session: createSession(user: valid, expiresAt: instant),
            ),
          ),
        ),
      ),
    ),
  );
  return switch (restored) {
    Ok(:final value) => value,
    Err() => null,
  };
}
