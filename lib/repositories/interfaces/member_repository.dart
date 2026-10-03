import '../../models/member.dart';

/// Persistence contract for committee members. Separate from
/// `CommitteeRepository` on purpose (Interface Segregation).
abstract interface class MemberRepository {
  Future<List<Member>> getByCommittee(String committeeId);
  Future<Member?> getById(String id);
  Future<Member?> getByTurn(String committeeId, int turnNumber);
  Future<String> insert(Member member);
  Future<void> update(Member member);
  Future<void> delete(String id);
  Future<int> countByCommittee(String committeeId);
  Future<int> nextTurnNumber(String committeeId);

  /// Bulk insert used while creating a committee inside a single transaction.
  Future<void> insertAll(List<Member> members);

  /// Applies a brand-new turn order (used by the "reorder turns" screen).
  /// The list must contain every member id of the committee exactly once.
  Future<void> reorder(String committeeId, List<String> orderedMemberIds);
  Future<void> deleteByCommittee(String committeeId);
}
