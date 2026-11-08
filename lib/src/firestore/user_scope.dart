import 'package:cloud_firestore/cloud_firestore.dart';

/// Scopes Firestore document and collection lookups to a signed-in user's
/// subtree (`{usersCollection}/{uid}`).
class UserScope {
  const UserScope(this.firestore, this.uid, {this.usersCollection = 'users'});

  final FirebaseFirestore firestore;
  final String uid;
  final String usersCollection;

  /// The user's root document (`{usersCollection}/{uid}`).
  DocumentReference<Map<String, dynamic>> get userDoc =>
      firestore.collection(usersCollection).doc(uid);

  /// Returns a [DocumentReference] relative to `{usersCollection}/{uid}`.
  ///
  /// When [path] is empty (or omitted), returns the user's root document
  /// (`{usersCollection}/{uid}`). Otherwise resolves [path] relative to
  /// `{usersCollection}/{uid}` (e.g. `'config/settings'`).
  DocumentReference<Map<String, dynamic>> doc([String path = '']) {
    final trimmed = _trimSlashes(path);
    if (trimmed.isEmpty) {
      return userDoc;
    }
    return firestore.doc('$usersCollection/$uid/$trimmed');
  }

  /// Returns a [CollectionReference] relative to `{usersCollection}/{uid}`
  /// (e.g. `'config'` -> `{usersCollection}/{uid}/config`).
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final trimmed = _trimSlashes(path);
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        path,
        'path',
        'Collection path must not be empty.',
      );
    }
    return firestore.collection('$usersCollection/$uid/$trimmed');
  }

  String _trimSlashes(String input) {
    var result = input.trim();
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
