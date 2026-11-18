/// Deterministic fingerprint for anything cached on disk.
///
/// `Object.hash` mixes a per-process seed, so a key built from it can never
/// match after a restart: the same catalogue and guide hash differently in the
/// next run. FNV-1a over the same fields does, and is cheap enough to fold over
/// a whole channel catalogue or guide snapshot.
class StableHash {
  StableHash([int seed = 0x811c9dc5]) : _value = seed & 0xFFFFFFFF;

  int _value;

  int get value => _value;

  void add(Object? field) {
    for (final unit in field.toString().codeUnits) {
      _value = ((_value ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    // Separate fields so ['ab', 'c'] and ['a', 'bc'] differ.
    _value = ((_value ^ 0x1f) * 0x01000193) & 0xFFFFFFFF;
  }

  static int of(Iterable<Object?> fields) {
    final hash = StableHash();
    for (final field in fields) {
      hash.add(field);
    }
    return hash.value;
  }
}
