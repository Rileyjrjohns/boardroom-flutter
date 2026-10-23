/// The errors of the votes: why a vote is refused (`VotingError`), and what can
/// go wrong between a vote being cast and the server recording it.
///
/// They extend the open `AppError` of the core. The two families are one
/// library (one `part` file each) because Dart only lets a sealed class be
/// extended inside its own library, and a `VotingError` is a `RejectionReason`,
/// which is sealed with the delivery errors: that is what makes a `switch` over
/// a reason, or over a family, exhaustive. Import this file to use any of them.
library;

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart' show ResolutionId;

part 'vote_delivery_error.dart';
part 'voting_error.dart';
