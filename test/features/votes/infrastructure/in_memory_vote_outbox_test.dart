import 'package:boardroom/features/votes/infrastructure/in_memory_vote_outbox.dart';

import '../../../support/contracts/vote_outbox_contract.dart';

void main() {
  describeVoteOutboxContract(
    'InMemoryVoteOutbox',
    () => VoteOutboxHarness(outbox: InMemoryVoteOutbox()),
    // It holds its entries as typed values: none can be unreadable.
    const VoteOutboxContractOptions(
      failsStatements: false,
      survivesReopen: false,
      holdsUnreadable: false,
    ),
  );
}
