import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin typed wrapper around a single Firestore [DocumentReference].
///
/// Loads, saves, and watches a JSON-backed model [T], returning [fallback]
/// whenever the document does not exist or fails to parse. Parse errors are
/// reported to [onParseError] when provided rather than swallowed silently.
class JsonDocument<T> {
  const JsonDocument({
    required this.ref,
    required this.fromJson,
    required this.toJson,
    required this.fallback,
    this.onParseError,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T value) toJson;
  final T fallback;
  final void Function(Object error, StackTrace stack)? onParseError;

  /// Reads the document once, returning [fallback] if it is missing or fails
  /// to parse.
  Future<T> load() async {
    final snap = await ref.get();
    return _decode(snap.data());
  }

  /// Writes [value] to the document using `set`. When [merge] is `true`,
  /// merges fields into any existing document instead of overwriting it.
  Future<void> save(T value, {bool merge = false}) async {
    if (merge) {
      await ref.set(toJson(value), SetOptions(merge: true));
    } else {
      await ref.set(toJson(value));
    }
  }

  /// Watches the document in real time, emitting [fallback] whenever the
  /// document is missing or fails to parse.
  Stream<T> watch() => ref.snapshots().map((snap) => _decode(snap.data()));

  T _decode(Map<String, dynamic>? data) {
    if (data == null) return fallback;
    try {
      return fromJson(data);
    } catch (error, stack) {
      onParseError?.call(error, stack);
      return fallback;
    }
  }
}
