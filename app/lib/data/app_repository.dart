import '../domain/models.dart';

class AppException implements Exception {
  const AppException(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

abstract class AppRepository {
  bool get isDemo;
  bool get isSignedIn;
  String? get currentUserId;
  Stream<bool> get authChanges;

  /// Permission-filtered invalidations. The snapshot remains the source of truth.
  Stream<void> get changes;
  Future<AppSnapshot> bootstrap();
  Future<Object?> action(String action, {JsonMap args = const {}});
  Future<PhotoRecognition> recognize(PhotoRecognitionRequest photo);
  Future<UploadedPhoto> upload(PhotoUpload photo);
  Future<void> sendEmailOtp(String email);
  Future<void> verifyEmailOtp(String email, String token);
  Future<void> signInWithApple();
  Future<void> signOut();
  Future<void> dispose();
}

/// Optional capability of the production repository; legacy/demo repositories
/// retain the existing broad invalidation contract.
abstract interface class ScopedRepository {
  Set<String> takeInvalidatedCollections();
}
