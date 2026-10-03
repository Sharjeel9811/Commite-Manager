import '../../models/committee.dart';

/// Persistence contract for committees.
///
/// **Interface Segregation:** this interface is intentionally tiny. Members,
/// payments and turns have their own interfaces, so a class (or a test double)
/// that only needs to read committees does not have to implement anything else.
abstract interface class CommitteeRepository {
  Future<List<Committee>> getAll();
  Future<List<Committee>> getByStatus(String status);
  Future<List<Committee>> search(String query);
  Future<Committee?> getById(String id);
  Future<String> insert(Committee committee);
  Future<void> update(Committee committee);
  Future<void> delete(String id);
  Future<int> count();
  Future<void> deleteAll();
}
