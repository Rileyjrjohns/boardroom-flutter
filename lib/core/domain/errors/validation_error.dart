part of 'app_error.dart';

/// The input a validation rule was applied to. The presentation maps it to a
/// form field or a label.
enum ValidationField implements StableValue {
  /// The id of a user.
  userId('userId'),

  /// The id of a meeting.
  meetingId('meetingId'),

  /// The id of an agenda item.
  agendaItemId('agendaItemId'),

  /// The id of a resolution.
  resolutionId('resolutionId'),

  /// The id of a document.
  documentId('documentId'),

  /// The full name of a user or of a participant.
  fullName('fullName'),

  /// An email address.
  email('email'),

  /// A password.
  password('password'),

  /// A title.
  title('title'),

  /// A description.
  description('description'),

  /// The location of a meeting.
  location('location'),

  /// The position of an agenda item.
  position('position'),

  /// The page count of a document.
  pageCount('pageCount'),

  /// The size of a page of a list.
  pageLimit('pageLimit'),

  /// The cursor of a page of a list.
  pageCursor('pageCursor'),

  /// A point in time.
  instant('instant'),

  /// A length of time.
  duration('duration'),

  /// The location of the content of a document.
  documentLocation('documentLocation'),

  /// The attempt count of a queued vote.
  attemptCount('attemptCount'),

  /// The agenda of a meeting.
  agenda('agenda'),

  /// The documents of a meeting.
  documents('documents'),

  /// The participants of a meeting.
  participants('participants'),

  /// The choice of a vote.
  voteChoice('voteChoice'),

  /// The period of a list of meetings.
  meetingPeriod('meetingPeriod'),

  /// The role of a participant.
  participantRole('participantRole'),

  /// The status of a resolution.
  resolutionStatus('resolutionStatus'),

  /// The confidentiality level of a document.
  confidentialityLevel('confidentialityLevel');

  new(this.value);

  @override
  final String value;
}

/// The rule that a value broke.
enum ValidationRule implements StableValue {
  /// Empty, blank or missing.
  required('required'),

  /// Longer than the maximum.
  tooLong('tooLong'),

  /// Not shaped as the value must be.
  invalidFormat('invalidFormat'),

  /// A number that is not a whole number.
  notAnInteger('notAnInteger'),

  /// A number outside its bounds.
  outOfRange('outOfRange'),

  /// Not a member of a closed set of values.
  unknownValue('unknownValue'),

  /// Two members of a collection that must be unique share an identity.
  duplicate('duplicate');

  new(this.value);

  @override
  final String value;
}

/// The codes of the validation errors.
enum ValidationErrorCode implements StableValue {
  /// A value broke an invariant.
  validation('validation');

  new(this.value);

  @override
  final String value;
}

/// A value broke an invariant: which input, which rule. Carries no text.
final class ValidationError extends AppError {
  /// Creates the error of the [rule] that the value of [field] broke.
  const new({required this.field, required this.rule});

  /// The input the rule was applied to.
  final ValidationField field;

  /// The rule the value broke.
  final ValidationRule rule;

  @override
  String get code => ValidationErrorCode.validation.value;

  @override
  Map<String, Object?> get payload => {'field': field, 'rule': rule};
}

/// Builds the [ValidationError] of the [rule] that the value of [field] broke.
ValidationError validationError(ValidationField field, ValidationRule rule) =>
    ValidationError(field: field, rule: rule);
