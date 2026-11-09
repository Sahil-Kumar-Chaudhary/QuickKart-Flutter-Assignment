// Feature 2, part 2: HomeLayout.parse contract (checked by hidden tests).
// The server-driven home must never break: unknown ids ignored, duplicates
// ignored, and any malformed input falls back to the default layout.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/home_layout.dart';

void main() {
  test('a well formed config keeps the configured order', () {
    expect(
      HomeLayout.parse(
        '["banner","categories","deals","all_products"]',
      ),
      const [
        HomeSection.banner,
        HomeSection.categories,
        HomeSection.deals,
        HomeSection.allProducts,
      ],
    );
  });

  test('any permutation is respected', () {
    expect(
      HomeLayout.parse('["deals","banner","categories"]'),
      const [
        HomeSection.deals,
        HomeSection.banner,
        HomeSection.categories,
      ],
    );
  });

  test('unknown section ids are ignored', () {
    expect(
      HomeLayout.parse('["banner","mystery","deals"]'),
      const [HomeSection.banner, HomeSection.deals],
    );
  });

  test('duplicates are ignored (first occurrence wins)', () {
    expect(
      HomeLayout.parse('["categories","deals","categories","banner"]'),
      const [
        HomeSection.categories,
        HomeSection.deals,
        HomeSection.banner,
      ],
    );
  });

  test('null falls back to the default layout', () {
    expect(HomeLayout.parse(null), HomeLayout.defaultSections);
  });

  test('malformed JSON falls back to the default layout', () {
    expect(HomeLayout.parse('not json at all'), HomeLayout.defaultSections);
    expect(HomeLayout.parse('["banner"'), HomeLayout.defaultSections);
  });

  test('a non-array value falls back to the default layout', () {
    expect(HomeLayout.parse('"banner"'), HomeLayout.defaultSections);
    expect(HomeLayout.parse('{"sections":[]}'), HomeLayout.defaultSections);
    expect(HomeLayout.parse('42'), HomeLayout.defaultSections);
  });

  test('an array with zero known sections falls back to the default layout', () {
    expect(HomeLayout.parse('["mystery"]'), HomeLayout.defaultSections);
    expect(HomeLayout.parse('[]'), HomeLayout.defaultSections);
  });

  test('non-string entries are ignored', () {
    expect(
      HomeLayout.parse('[42,null,true,"deals"]'),
      const [HomeSection.deals],
    );
  });

  test('entries are matched exactly (no trimming / case folding)', () {
    expect(HomeLayout.parse('[" BANNER "]'), HomeLayout.defaultSections);
    expect(HomeLayout.parse('["Banner"]'), HomeLayout.defaultSections);
  });
}
