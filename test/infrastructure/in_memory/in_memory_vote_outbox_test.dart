import 'package:boardroom/infrastructure/in_memory/in_memory_vote_outbox.dart';

import '../../application/support/contracts/vote_outbox_contract.dart';

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
