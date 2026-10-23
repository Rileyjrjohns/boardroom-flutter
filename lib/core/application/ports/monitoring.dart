import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';

/// How serious a log line is.
enum LogLevel implements StableValue {
  /// Expected behaviour worth counting (a copy served from the cache, a vote
  /// recorded).
  info('info'),

  /// Something that deserves attention (a vote refused, a capture detected, a
  /// run interrupted).
  warn('warn');

  new(this.value);

  @override
  final String value;
}

/// Every event the application reports. A call site names one of these, never a
/// free text, so the events can be counted, alerted on and searched for.
enum MonitoringEvent implements StableValue {
  /// A stored session was found expired at the start and ended.
  sessionExpired('sessionExpired'),

  /// The session could not be forgotten while it was being ended.
  signOutFailed('signOutFailed'),

  /// A local cache could not be read; the read is treated as a miss.
  cacheReadFailed('cacheReadFailed'),

  /// A local cache could not be written; the fresh data is returned all the
  /// same.
  cacheWriteFailed('cacheWriteFailed'),

  /// An entry could not be removed from a cache.
  cacheRemoveFailed('cacheRemoveFailed'),

  /// A cache could not be emptied.
  cachePurgeFailed('cachePurgeFailed'),

  /// A cached entry was too old, or dated in the future, and counted as a miss.
  cacheEntryDiscarded('cacheEntryDiscarded'),

  /// The server was unreachable and a saved copy was served as stale data.
  servedFromCache('servedFromCache'),

  /// A document was opened (the access log).
  documentOpened('documentOpened'),

  /// A screenshot or recording was reported while a document was shown.
  screenCaptureDetected('screenCaptureDetected'),

  /// The server recorded a vote.
  voteSubmitted('voteSubmitted'),

  /// Sending a vote failed unexpectedly; it counts as an attempt.
  voteSubmitFailed('voteSubmitFailed'),

  /// A vote that could not be delivered was put in the outbox.
  voteQueued('voteQueued'),

  /// A vote could not be put in the outbox.
  voteEnqueueFailed('voteEnqueueFailed'),

  /// A vote was refused for a business reason, or given up after too many
  /// attempts.
  voteRejected('voteRejected'),

  /// An attempt could not be counted on a pending vote.
  voteAttemptNotRecorded('voteAttemptNotRecorded'),

  /// A synchronisation run went through the whole queue.
  voteSyncCompleted('voteSyncCompleted'),

  /// A synchronisation run stopped early on a condition that concerns every
  /// vote.
  voteSyncInterrupted('voteSyncInterrupted'),

  /// The outbox could not be read when counting the votes that remain.
  outboxReadFailed('outboxReadFailed'),

  /// A row of the local database no longer reads back as what was stored: it is
  /// dropped.
  storedRowDiscarded('storedRowDiscarded'),

  /// The content of a document was downloaded and could not be written to the
  /// files of the device. The document is not shown.
  documentContentNotStored('documentContentNotStored'),

  /// The files of the documents that no entry points at could not all be
  /// deleted when the app started. What is left waits for the next start.
  /// Reported once per start, without file names.
  orphanFileNotDeleted('orphanFileNotDeleted'),

  /// An entry of the outbox of votes no longer reads back as a vote: it is
  /// kept, out of the queue, until the user discards it.
  storedRowQuarantined('storedRowQuarantined'),

  /// The server answered something that does not have the shape of the API.
  responseInvalid('responseInvalid'),

  /// The local database could not be opened with its key: the file was set
  /// aside, unread, and a new one was created, empty. Votes that waited in the
  /// old one are not in the new one.
  databaseRecreated('databaseRecreated'),

  /// A listener of the connectivity threw, which it must not. The others were
  /// told all the same.
  connectivityListenerFailed('connectivityListenerFailed'),

  /// A listener of the screen capture events threw, which it must not. The
  /// others were told all the same.
  screenProtectionListenerFailed('screenProtectionListenerFailed'),

  /// The native side of the screen protection failed or did not answer: the
  /// failure is also returned.
  screenProtectionNativeFailed('screenProtectionNativeFailed'),

  /// The build lacks what the platform needs to ask for the biometrics (a usage
  /// description on iOS).
  biometricMisconfigured('biometricMisconfigured'),

  /// The user asked for the entries of the outbox that cannot be read to be
  /// deleted.
  unreadableVotesDiscarded('unreadableVotesDiscarded'),

  /// The crash reporter was asked for and could not be started (its address is
  /// not valid, or the SDK failed): the app goes on with the console, and the
  /// reason says which.
  monitoringNotStarted('monitoringNotStarted'),

  /// The record that local data was reset could not be read, so the user may
  /// not be told.
  resetNoticeUnreadable('resetNoticeUnreadable'),

  /// The user has been told local data was reset, and the record of it could
  /// not be cleared.
  resetNoticeNotCleared('resetNoticeNotCleared');

  new(this.value);

  @override
  final String value;
}

/// The names an event can carry data under. Identifiers, codes and counts only:
/// never a name, an email, a password, the content of a document, nor the
/// choice of a vote (the ballot is secret).
enum LogAttribute implements StableValue {
  /// Identifier of the user concerned.
  userId('userId'),

  /// Identifier of the meeting concerned.
  meetingId('meetingId'),

  /// Identifier of the resolution concerned.
  resolutionId('resolutionId'),

  /// Identifier of the document concerned.
  documentId('documentId'),

  /// The meeting period of a list.
  period('period'),

  /// What was being cached or stored.
  resource('resource'),

  /// Whether data came straight from the server or from the cache.
  freshness('freshness'),

  /// The confidentiality level of a document.
  confidentiality('confidentiality'),

  /// A value of the kinds of screen capture.
  captureKind('captureKind'),

  /// The stable code of an error.
  errorCode('errorCode'),

  /// A number of attempts to deliver a vote.
  attempts('attempts'),

  /// The number of votes the server recorded in a run.
  synced('synced'),

  /// The number of votes moved to the rejected state in a run.
  rejected('rejected'),

  /// The number of pending votes left after a run.
  remaining('remaining'),

  /// The number of unreadable entries deleted at the user's request.
  discarded('discarded'),

  /// The places a payload broke the schema (`agenda.0.status`), never what it
  /// held.
  issuePaths('issuePaths'),

  /// Why something happened, as one of the constant sets of the code that
  /// reports it.
  reason('reason');

  new(this.value);

  @override
  final String value;
}

/// The data of an event, by name: each value is a `String`, a number or a
/// `bool`. Only the attributes that apply are present.
typedef LogAttributes = Map<LogAttribute, Object>;

/// Structured logs and error reports, sent to whatever tool the adapter wraps.
/// Fire and forget: both methods return nothing, return at once, wait for
/// nothing and never throw, whatever happens to the tool behind them. The
/// `cause` of an error may reach the tool, and it holds a status code or a kind
/// of failure, nothing else: neither it nor any attribute is ever a file path,
/// a URL, the location of a document or its title, a name, an email, nor the
/// choice of a vote (the ballot is secret). Identifiers and codes only (see the
/// errors).
///
/// The convention in the use cases: an error that is returned to the caller is
/// the caller's to report; an error that a use case swallows (a cache that
/// cannot be written, say) is captured here, so that it does not vanish.
abstract interface class Monitoring {
  /// Logs [event] at [level].
  void log(LogLevel level, MonitoringEvent event, [LogAttributes? attributes]);

  /// Reports [error] for [event].
  void captureError(
    MonitoringEvent event,
    AppError error, [
    LogAttributes? attributes,
  ]);
}
