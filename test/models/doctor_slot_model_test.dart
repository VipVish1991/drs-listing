import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/doctor_slot_model.dart';
import 'package:DrsListing/utils/time_slot_generator.dart';
import '../helpers/test_data.dart';

void main() {
  group('DoctorSlot', () {
    group('fromJson', () {
      test('parses all fields correctly', () {
        final json = <String, dynamic>{
          'id': 'slot_001',
          'doctor_place_id': 'place_test_1',
          'day_of_week': 'Monday',
          'schedule_type': 'video',
          'start_time': '09:00',
          'end_time': '12:00',
          'duration_minutes': 30,
          'fee': 800,
          'slots': ['9:00 AM', '9:30 AM', '10:00 AM'],
          'is_enabled': true,
          'created_at': '2026-07-20T10:00:00Z',
          'updated_at': '2026-07-20T10:30:00Z',
        };

        final slot = DoctorSlot.fromJson(json);

        expect(slot.id, 'slot_001');
        expect(slot.doctorPlaceId, 'place_test_1');
        expect(slot.dayOfWeek, 'Monday');
        expect(slot.scheduleType, 'video');
        expect(slot.startTime, '09:00');
        expect(slot.endTime, '12:00');
        expect(slot.durationMinutes, 30);
        expect(slot.fee, 800);
        expect(slot.slots, ['9:00 AM', '9:30 AM', '10:00 AM']);
        expect(slot.isEnabled, isTrue);
        expect(slot.createdAt, DateTime.utc(2026, 7, 20, 10, 0, 0));
        expect(slot.updatedAt, DateTime.utc(2026, 7, 20, 10, 30, 0));
      });

      test('parses tele consultation type', () {
        final json = <String, dynamic>{
          'doctor_place_id': 'place_1',
          'day_of_week': 'Tuesday',
          'schedule_type': 'tele',
          'start_time': '14:00',
          'end_time': '17:00',
        };
        final slot = DoctorSlot.fromJson(json);
        expect(slot.scheduleType, 'tele');
        expect(slot.startTime, '14:00');
        expect(slot.endTime, '17:00');
      });

      test('parses clinic consultation type', () {
        final json = <String, dynamic>{
          'doctor_place_id': 'place_1',
          'day_of_week': 'Wednesday',
          'schedule_type': 'clinic',
          'start_time': '10:00',
          'end_time': '16:00',
        };
        final slot = DoctorSlot.fromJson(json);
        expect(slot.scheduleType, 'clinic');
        expect(slot.startTime, '10:00');
      });

      test('uses defaults for missing optional fields', () {
        final json = <String, dynamic>{
          'doctor_place_id': 'place_1',
          'day_of_week': 'Monday',
          'schedule_type': 'video',
          'start_time': '09:00',
          'end_time': '12:00',
        };

        final slot = DoctorSlot.fromJson(json);

        expect(slot.id, isNull);
        expect(slot.durationMinutes, 30); // default
        expect(slot.fee, 0); // default
        expect(slot.slots, isEmpty); // default
        expect(slot.isEnabled, isTrue); // default
        expect(slot.createdAt, isNull);
        expect(slot.updatedAt, isNull);
      });

      test('handles empty JSON gracefully', () {
        final json = <String, dynamic>{};
        final slot = DoctorSlot.fromJson(json);

        expect(slot.doctorPlaceId, '');
        expect(slot.dayOfWeek, '');
        expect(slot.scheduleType, '');
        expect(slot.startTime, '09:00'); // default
        expect(slot.endTime, '12:00'); // default
        expect(slot.slots, isEmpty);
        expect(slot.isEnabled, isTrue);
      });

      test('handles is_enabled = false', () {
        final json = <String, dynamic>{
          'doctor_place_id': 'place_1',
          'day_of_week': 'Sunday',
          'schedule_type': 'clinic',
          'start_time': '10:00',
          'end_time': '13:00',
          'is_enabled': false,
        };

        final slot = DoctorSlot.fromJson(json);
        expect(slot.isEnabled, isFalse);
      });
    });

    group('toJson', () {
      test('serializes all fields correctly', () {
        final slot = doctorSlotBasic(id: 'slot_001');
        final json = slot.toJson();

        expect(json['id'], 'slot_001');
        expect(json['doctor_place_id'], 'place_test_1');
        expect(json['day_of_week'], 'Monday');
        expect(json['schedule_type'], 'video');
        expect(json['start_time'], '09:00');
        expect(json['end_time'], '12:00');
        expect(json['duration_minutes'], 30);
        expect(json['fee'], 800);
        expect(json['slots'], isA<List>());
        expect(json['is_enabled'], isTrue);
      });

      test('omits id when null', () {
        final slot = doctorSlotBasic(id: null);
        final json = slot.toJson();

        expect(json.containsKey('id'), isFalse);
      });

      test('round-trips through fromJson → toJson → fromJson', () {
        final original = doctorSlotBasic(id: 'slot_rt');
        final json = original.toJson();
        final restored = DoctorSlot.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.doctorPlaceId, original.doctorPlaceId);
        expect(restored.dayOfWeek, original.dayOfWeek);
        expect(restored.scheduleType, original.scheduleType);
        expect(restored.startTime, original.startTime);
        expect(restored.endTime, original.endTime);
        expect(restored.durationMinutes, original.durationMinutes);
        expect(restored.fee, original.fee);
        expect(restored.slots, original.slots);
        expect(restored.isEnabled, original.isEnabled);
      });
    });

    group('copyWith', () {
      test('returns identical copy when no args provided', () {
        final original = doctorSlotBasic(id: 'slot_cw');
        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.doctorPlaceId, original.doctorPlaceId);
        expect(copy.dayOfWeek, original.dayOfWeek);
        expect(copy.scheduleType, original.scheduleType);
        expect(copy.startTime, original.startTime);
      });

      test('overrides specified fields', () {
        final original = doctorSlotBasic(id: 'slot_cw2');
        final copy = original.copyWith(
          dayOfWeek: 'Friday',
          startTime: '10:00',
          fee: 1000,
          isEnabled: false,
        );

        expect(copy.dayOfWeek, 'Friday');
        expect(copy.startTime, '10:00');
        expect(copy.fee, 1000);
        expect(copy.isEnabled, isFalse);
        // Unchanged
        expect(copy.id, 'slot_cw2');
        expect(copy.doctorPlaceId, 'place_test_1');
      });

      test('can set id from null to non-null', () {
        final original = doctorSlotBasic(id: null);
        final copy = original.copyWith(id: 'new_id');
        expect(copy.id, 'new_id');
      });
    });

    group('type getters', () {
      test('typeLabel returns correct emoji + label for tele', () {
        final slot = doctorSlotBasic(scheduleType: 'tele');
        expect(slot.typeLabel, contains('📞'));
        expect(slot.typeLabel, contains('Tele'));
      });

      test('typeLabel returns correct emoji + label for video', () {
        final slot = doctorSlotBasic(scheduleType: 'video');
        expect(slot.typeLabel, contains('🎥'));
        expect(slot.typeLabel, contains('Video'));
      });

      test('typeLabel returns correct emoji + label for clinic', () {
        final slot = doctorSlotBasic(scheduleType: 'clinic');
        expect(slot.typeLabel, contains('🏥'));
        expect(slot.typeLabel, contains('Clinic'));
      });

      test('typeLabel fallback for unknown type', () {
        final slot = doctorSlotBasic(scheduleType: 'unknown');
        expect(slot.typeLabel, 'unknown');
      });

      test('typeSubtitle returns correct sub-label for tele', () {
        final slot = doctorSlotBasic(scheduleType: 'tele');
        expect(slot.typeSubtitle, contains('Phone'));
      });

      test('typeSubtitle returns correct sub-label for video', () {
        final slot = doctorSlotBasic(scheduleType: 'video');
        expect(slot.typeSubtitle, contains('Video'));
      });

      test('typeSubtitle returns correct sub-label for clinic', () {
        final slot = doctorSlotBasic(scheduleType: 'clinic');
        expect(slot.typeSubtitle, contains('Physical'));
      });

      test('typeSubtitle returns empty string for unknown', () {
        final slot = doctorSlotBasic(scheduleType: 'unknown');
        expect(slot.typeSubtitle, '');
      });

      test('typeEmoji returns correct emoji', () {
        expect(doctorSlotBasic(scheduleType: 'tele').typeEmoji, '📞');
        expect(doctorSlotBasic(scheduleType: 'video').typeEmoji, '🎥');
        expect(doctorSlotBasic(scheduleType: 'clinic').typeEmoji, '🏥');
        expect(doctorSlotBasic(scheduleType: 'unknown').typeEmoji, '🩺');
      });
    });

    group('generateTimeSlots', () {
      test('generates 6 slots for 09:00-12:00 at 30min intervals', () {
        final slots = generateTimeSlots('09:00', '12:00', 30);
        expect(slots.length, 6);
        expect(slots[0], '9:00 AM');
        expect(slots[1], '9:30 AM');
        expect(slots[2], '10:00 AM');
        expect(slots[3], '10:30 AM');
        expect(slots[4], '11:00 AM');
        expect(slots[5], '11:30 AM');
      });

      test('generates 4 slots for 09:00-11:00 at 30min intervals', () {
        final slots = generateTimeSlots('09:00', '11:00', 30);
        expect(slots.length, 4);
        expect(slots[0], '9:00 AM');
        expect(slots[3], '10:30 AM');
      });

      test('generates single slot for 09:00-09:30', () {
        final slots = generateTimeSlots('09:00', '09:30', 30);
        expect(slots.length, 1);
        expect(slots[0], '9:00 AM');
      });

      test('returns empty list when start equals end', () {
        final slots = generateTimeSlots('10:00', '10:00', 30);
        expect(slots, isEmpty);
      });

      test('handles PM times correctly', () {
        final slots = generateTimeSlots('13:00', '15:00', 30);
        expect(slots.length, 4);
        expect(slots[0], '1:00 PM');
        expect(slots[1], '1:30 PM');
        expect(slots[2], '2:00 PM');
        expect(slots[3], '2:30 PM');
      });

      test('handles 12:00 PM correctly (noon)', () {
        final slots = generateTimeSlots('12:00', '13:00', 30);
        expect(slots.length, 2);
        expect(slots[0], '12:00 PM');
        expect(slots[1], '12:30 PM');
      });

      test('handles 15min intervals', () {
        final slots = generateTimeSlots('09:00', '10:00', 15);
        expect(slots.length, 4);
        expect(slots[0], '9:00 AM');
        expect(slots[1], '9:15 AM');
        expect(slots[2], '9:30 AM');
        expect(slots[3], '9:45 AM');
      });

      test('handles 60min intervals', () {
        final slots = generateTimeSlots('09:00', '17:00', 60);
        expect(slots.length, 8);
        expect(slots[0], '9:00 AM');
        expect(slots[7], '4:00 PM');
      });

      test('does not include end time slot (exclusive)', () {
        final slots = generateTimeSlots('09:00', '10:00', 30);
        expect(slots, ['9:00 AM', '9:30 AM']);
        expect(slots, isNot(contains('10:00 AM')));
      });

      test('handles evening PM times correctly', () {
        final slots = generateTimeSlots('18:00', '20:00', 30);
        expect(slots.length, 4);
        expect(slots[0], '6:00 PM');
        expect(slots[3], '7:30 PM');
      });

      test('handles 5min intervals for large range', () {
        final slots = generateTimeSlots('09:00', '10:00', 5);
        expect(slots.length, 12); // 60 min / 5 min = 12 slots
        expect(slots[0], '9:00 AM');
        expect(slots[11], '9:55 AM');
      });

      test('duration of 0 returns empty list (prevents infinite loop)', () {
        final slots = generateTimeSlots('09:00', '17:00', 0);
        expect(slots, isEmpty);
      });
    });
  });
}
