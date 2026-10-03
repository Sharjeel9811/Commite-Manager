import '../../models/app_user.dart';
import '../../models/otp_challenge.dart';

/// Persistence contract for the local account.
///
/// Split in two on purpose (Interface Segregation): account storage and OTP
/// challenge storage have completely different lifetimes and rules.
abstract interface class UserRepository {
  Future<AppUser?> getPrimary();
  Future<AppUser?> getById(String id);
  Future<String> insert(AppUser user);
  Future<void> update(AppUser user);
  Future<void> delete(String id);
  Future<bool> exists();
}

abstract interface class OtpRepository {
  Future<String> insert(OtpChallenge challenge);
  Future<OtpChallenge?> getLatestOpen(String userId);
  Future<void> incrementAttempts(String challengeId);
  Future<void> markConsumed(String challengeId, DateTime when);
  Future<void> invalidateAll(String userId);
  Future<int> countRecent(String userId, DateTime since);
}
