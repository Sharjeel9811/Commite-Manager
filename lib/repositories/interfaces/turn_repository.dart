import '../../models/committee_turn.dart';

/// Persistence contract for the collection order (turns).
abstract interface class TurnRepository {
  Future<List<CommitteeTurn>> getByCommittee(String committeeId);
  Future<CommitteeTurn?> getByNumber(String committeeId, int turnNumber);
  Future<CommitteeTurn?> getActive(String committeeId);
  Future<CommitteeTurn?> getByMember(String memberId);
  Future<void> insertAll(List<CommitteeTurn> turns);
  Future<void> update(CommitteeTurn turn);
  Future<void> updateCollected(String turnId, double collectedAmount);
  Future<void> deleteByCommittee(String committeeId);
  Future<int> countCompleted(String committeeId);
  Future<int> countAll();
  Future<int> countCompletedAll();
  Future<int> sumExpectedAll();
  Future<int> sumCollectedAll();
}
