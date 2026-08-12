import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/unavailable_range.dart';

void main() {
  group('UnavailableRange', () {
    test('contains() is inclusive of both ends', () {
      final range = UnavailableRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 12),
      );
      expect(range.contains(DateTime(2026, 8, 9)), isFalse);
      expect(range.contains(DateTime(2026, 8, 10)), isTrue);
      expect(range.contains(DateTime(2026, 8, 11)), isTrue);
      expect(range.contains(DateTime(2026, 8, 12)), isTrue);
      expect(range.contains(DateTime(2026, 8, 13)), isFalse);
    });

    test('contains() ignores the time of day', () {
      final range = UnavailableRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 12),
      );
      expect(range.contains(DateTime(2026, 8, 10, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 8, 12, 0, 1)), isTrue);
    });

    test('constructor normalizes DateTime.now() time-of-day to midnight', () {
      // A range built from DateTime.now() (which carries hours/minutes) must
      // still contain its own start/end dates — otherwise booking screens
      // that build ranges from "today" never match today.
      final now = DateTime.now();
      final range = UnavailableRange(start: now, end: now);
      expect(range.start, DateTime(now.year, now.month, now.day));
      expect(range.end, DateTime(now.year, now.month, now.day));
      expect(range.contains(now), isTrue);
      expect(
        range.contains(
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        ),
        isTrue,
      );
    });

    test('toJson uses YYYY-MM-DD start/end keys', () {
      final range = UnavailableRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 12),
      );
      expect(range.toJson(), {'start': '2026-08-10', 'end': '2026-08-12'});
    });

    test('round-trips through fromJson', () {
      final range = UnavailableRange.fromJson({
        'start': '2026-08-10',
        'end': '2026-08-12',
      });
      expect(range.start, DateTime(2026, 8, 10));
      expect(range.end, DateTime(2026, 8, 12));
      expect(range.toJson()['start'], '2026-08-10');
      expect(range.toJson()['end'], '2026-08-12');
    });

    test(
      'normalizes a reversed range (start after end) instead of throwing',
      () {
        final range = UnavailableRange.fromJson({
          'start': '2026-08-12',
          'end': '2026-08-10',
        });
        expect(range.start, DateTime(2026, 8, 10));
        expect(range.end, DateTime(2026, 8, 12));
      },
    );

    test('label is human readable', () {
      final range = UnavailableRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 12),
      );
      expect(range.label, '10 Aug 2026 – 12 Aug 2026');
    });

    test('listFromJson skips malformed entries', () {
      final ranges = UnavailableRange.listFromJson([
        {'start': '2026-08-10', 'end': '2026-08-12'},
        'not-a-map',
        42,
        {'start': '2026-09-01', 'end': '2026-09-02'},
      ]);
      expect(ranges.length, 2);
      expect(ranges[0].start, DateTime(2026, 8, 10));
      expect(ranges[1].end, DateTime(2026, 9, 2));
    });

    test('listFromJson handles non-list input', () {
      expect(UnavailableRange.listFromJson(null), isEmpty);
      expect(UnavailableRange.listFromJson('oops'), isEmpty);
    });

    test('matchingIsoDates returns only dates inside any range', () {
      final ranges = [
        UnavailableRange(
          start: DateTime(2026, 8, 10),
          end: DateTime(2026, 8, 12),
        ),
      ];
      const dates = [
        '2026-08-09',
        '2026-08-10',
        '2026-08-11',
        '2026-08-12',
        '2026-08-13',
      ];
      expect(UnavailableRange.matchingIsoDates(dates, ranges), {
        '2026-08-10',
        '2026-08-11',
        '2026-08-12',
      });
    });

    test('matchingIsoDates with no ranges returns empty', () {
      expect(
        UnavailableRange.matchingIsoDates(['2026-08-10'], const []),
        isEmpty,
      );
    });
  });
}
