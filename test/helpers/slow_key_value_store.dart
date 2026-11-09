import 'package:quickkart/core/storage/key_value_store.dart';

/// An in-memory [KeyValueStore] that yields before every write and read, so
/// tests can exercise concurrent mutations the way a real device does.
class SlowKeyValueStore implements KeyValueStore {
  SlowKeyValueStore({this.delay = const Duration(milliseconds: 20)});

  final Duration delay;
  final Map<String, String> _data = {};

  Map<String, String> get snapshot => Map.unmodifiable(_data);

  Future<void> _wait() => Future<void>.delayed(delay);

  @override
  Future<String?> getString(String key) async {
    await _wait();
    return _data[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    await _wait();
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    await _wait();
    _data.remove(key);
  }

  @override
  Future<Set<String>> keys() async {
    await _wait();
    return _data.keys.toSet();
  }
}
