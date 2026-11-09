// Feature 2, part 1: UpdatePolicy.evaluate contract (checked by hidden
// tests, see update_policy.dart).
//
// The gate must never lock users out because of a config typo, so any
// malformed version means "no action".
import 'package:quickkart/features/app_config/domain/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('numeric ordering', () {
    test('current below minSupported is required', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.3.2',
          minSupportedVersion: '2.0.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.required,
      );
    });

    test('current below latest is optional', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: '1.2.0',
          latestVersion: '1.5.0',
        ),
        UpdateRequirement.optional,
      );
    });

    test('current equal to latest is none', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: '1.2.0',
          latestVersion: '1.4.0',
        ),
        UpdateRequirement.none,
      );
    });

    test('comparison is numeric, not lexicographic (1.10 > 1.9)', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.10.2',
          minSupportedVersion: '1.9.0',
          latestVersion: '1.9.9',
        ),
        UpdateRequirement.none,
      );
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.9.9',
          minSupportedVersion: '1.2.0',
          latestVersion: '1.10.0',
        ),
        UpdateRequirement.optional,
      );
    });

    test('missing segments count as zero (1.4 == 1.4.0)', () {
      // 1.4.0 equals the minimum (1.4.0) so it is not blocked, but is below
      // the latest (2.0.0): optional.
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4',
          minSupportedVersion: '1.4.0',
          latestVersion: '2.0',
        ),
        UpdateRequirement.optional,
      );
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.4.0',
          minSupportedVersion: '2.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.required,
      );
    });

    test('required wins when current is below both', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.0.0',
          minSupportedVersion: '1.2.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.required,
      );
    });
  });

  group('malformed values never lock the app', () {
    test('a malformed current version', () {
      for (final v in const ['', 'x', '1.4.x', 'latest', '1.4.0-beta', '-1.4']) {
        expect(
          UpdatePolicy.evaluate(
            currentVersion: v,
            minSupportedVersion: '1.0.0',
            latestVersion: '2.0.0',
          ),
          UpdateRequirement.none,
          reason: 'malformed current "$v" must mean none',
        );
      }
    });

    test('a malformed minSupported version', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.0.0',
          minSupportedVersion: '',
          latestVersion: '9.9.9',
        ),
        UpdateRequirement.none,
      );
      // Even though current < latest, the malformed minSupported value
      // blinds the gate: must be none, never optional.
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.0.0',
          minSupportedVersion: '2.x.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );
    });

    test('a malformed latest version', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.0.0',
          minSupportedVersion: '0.5.0',
          latestVersion: '',
        ),
        UpdateRequirement.none,
      );
      // Current < minSupported AND latest malformed: still none, because a
      // bad value in the console must never lock users out.
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '0.1.0',
          minSupportedVersion: '1.0.0',
          latestVersion: 'oops',
        ),
        UpdateRequirement.none,
      );
    });

    test('empty segments are malformed', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: '1.0.0',
          minSupportedVersion: '1..0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
      );
    });

    test('whitespace-only and dotted variants', () {
      expect(
        UpdatePolicy.evaluate(
          currentVersion: ' 1.0.0',
          minSupportedVersion: '1.0.0',
          latestVersion: '2.0.0',
        ),
        UpdateRequirement.none,
        reason: 'leading whitespace is malformed',
      );
    });
  });
}
