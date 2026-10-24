import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/active_event.dart';
import 'package:spectrumpit/src/ui/event_picker_sheet.dart';

void main() {
  group('isEventNearby', () {
    final today = DateTime(2026, 3, 10, 15, 30);

    test('an event in progress is nearby', () {
      expect(isEventNearby('2026-03-09', '2026-03-11', today), isTrue);
    });

    test('an event starting within three days is nearby', () {
      expect(isEventNearby('2026-03-13', '2026-03-15', today), isTrue);
      expect(isEventNearby('2026-03-14', '2026-03-16', today), isFalse);
    });

    test('an event that ended within three days is nearby', () {
      expect(isEventNearby('2026-03-05', '2026-03-07', today), isTrue);
      expect(isEventNearby('2026-03-04', '2026-03-06', today), isFalse);
    });

    test('a missing end date counts as a one-day event', () {
      expect(isEventNearby('2026-03-13', null, today), isTrue);
      expect(isEventNearby('2026-03-06', null, today), isFalse);
    });

    test('an event with no start date is never nearby', () {
      expect(isEventNearby(null, '2026-03-10', today), isFalse);
      expect(isEventNearby('soon', '2026-03-10', today), isFalse);
    });

    test('the window counts calendar days across a month end', () {
      final endOfMonth = DateTime(2026, 3, 30);
      expect(isEventNearby('2026-04-02', '2026-04-04', endOfMonth), isTrue);
      expect(isEventNearby('2026-04-03', '2026-04-04', endOfMonth), isFalse);
    });
  });

  group('ActiveEvent.fromJson', () {
    test('a missing or empty key is no event', () {
      expect(ActiveEvent.fromJson(null), isNull);
      expect(ActiveEvent.fromJson({'eventKey': ''}), isNull);
    });

    test('round-trips through toJson', () {
      final event = ActiveEvent(
        eventKey: '2026txcl2',
        eventName: 'Lone Star Central',
        updatedAt: DateTime.utc(2026, 3, 1),
      );
      expect(ActiveEvent.fromJson(event.toJson()), event);
    });
  });

  group('formatEventDates', () {
    test('formats one month, two months, and one day', () {
      expect(formatEventDates('2026-03-12', '2026-03-14'), 'MAR 12-14');
      expect(formatEventDates('2026-03-30', '2026-04-02'), 'MAR 30-APR 2');
      expect(formatEventDates('2026-03-12', null), 'MAR 12');
      expect(formatEventDates(null, '2026-03-12'), '');
    });
  });
}
