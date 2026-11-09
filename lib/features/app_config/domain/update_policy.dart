/// What the app must do about its own version.
enum UpdateRequirement {
  /// Nothing to do.
  none,

  /// A newer version exists; the user may update or dismiss.
  optional,

  /// This version is no longer supported; the app must be blocked until the
  /// user updates.
  required,
}

/// Decides whether the running app must / may be updated.
///
/// ## Contract (hidden tests check this exactly - see ASSIGNMENT.md, F2):
/// * Versions are dotted numbers like `1.4.0`, `1.10.2`, `2.0`. Compare them
///   numerically, segment by segment. Missing segments count as 0
///   (`1.4` == `1.4.0`).
/// * `current < minSupported`  -> [UpdateRequirement.required]
/// * `current < latest`        -> [UpdateRequirement.optional]
/// * otherwise                 -> [UpdateRequirement.none]
/// * If ANY of the three versions is malformed (empty, letters, negative
///   numbers, ...) return [UpdateRequirement.none]. A bad value in the
///   config console must never lock users out of the app.
class UpdatePolicy {
  const UpdatePolicy._();

  /// Matches `1.2`, `1.2.3`, `10.20.30` - digit segments only.
  static final RegExp _pattern = RegExp(r'^\d+(\.\d+)*$');

  /// Parses a dotted version into comparable numbers, or null when malformed.
  static List<int>? parseVersion(String version) {
    if (!_pattern.hasMatch(version)) return null;
    return version.split('.').map(int.parse).toList();
  }

  /// Segment-wise numeric comparison; missing segments count as 0.
  static int compare(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static UpdateRequirement evaluate({
    required String currentVersion,
    required String minSupportedVersion,
    required String latestVersion,
  }) {
    final current = parseVersion(currentVersion);
    final minSupported = parseVersion(minSupportedVersion);
    final latest = parseVersion(latestVersion);
    // A malformed value in the config console must never lock users out.
    if (current == null || minSupported == null || latest == null) {
      return UpdateRequirement.none;
    }
    if (compare(current, minSupported) < 0) {
      return UpdateRequirement.required;
    }
    if (compare(current, latest) < 0) {
      return UpdateRequirement.optional;
    }
    return UpdateRequirement.none;
  }
}
