import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Default static room used as fallback when no rooms in the pool are
/// available (legacy rows without a stored link).
const String kFallbackMeetLink = 'https://meet.google.com/rnz-wivx-yze';

/// How long a room stays "in_use" before auto-expiring (safety net for
/// abandoned meetings). The Dart side sets this when allocating; the DB
/// expires rows whose `expires_at` has passed.
const Duration kRoomAllocationTtl = Duration(hours: 2);

/// Manages the Google Meet room pool in Supabase:
///
///   1. **Allocate** — picks the first `available` room and marks it
///      `in_use` for a specific appointment. If no rooms are free, falls
///      back to the static room URL stored on the appointment (or the
///      hardcoded fallback).
///   2. **Free** — marks a room `available` again when the consultation
///      ends (Complete / Cancelled).
///   3. **Cleanup** — releases all `in_use` rooms whose `expires_at` has
///      passed (call on app start or periodically).
///
/// All methods are fire-and-forget safe: a failure is logged and returns
/// a degraded result (the fallback room) so the consultation can proceed.
class RoomAllocationService {
  RoomAllocationService._();

  static final RoomAllocationService instance = RoomAllocationService._();

  SupabaseClient? _client;
  SupabaseClient get client => _client ??= Supabase.instance.client;

  /// Allocate a free room for [appointmentId].
  ///
  /// Returns the room URL on success, or a fallback link if:
  ///   - No rooms are available (all in_use / not yet seeded).
  ///   - The DB write fails (network, RLS).
  ///
  /// The room is marked `in_use` with an expiry of [kRoomAllocationTtl]
  /// from now. If the appointment already has an allocated room, that same
  /// room is returned (idempotent).
  Future<String> allocateRoom({
    required String appointmentId,
    String? doctorPlaceId,
    String? patientUserId,
    String? existingMeetLink,
  }) async {
    try {
      // 1. Check if this appointment already has a room allocated.
      final existing = await client
          .from('meeting_rooms')
          .select('room_url')
          .eq('appointment_id', appointmentId)
          .eq('status', 'in_use')
          .maybeSingle();
      if (existing != null && existing['room_url'] != null) {
        debugPrint(
          '✅ [RoomAllocation] room already allocated for '
          '$appointmentId: ${existing['room_url']}',
        );
        return existing['room_url'] as String;
      }

      // 2. Find the first available room.
      final free = await client
          .from('meeting_rooms')
          .select('id, room_url')
          .eq('status', 'available')
          .order('created_at')
          .limit(1)
          .maybeSingle();

      if (free == null || free['id'] == null) {
        // No free rooms — fall back to the appointment's stored link
        // or the hardcoded static room.
        final fallback =
            (existingMeetLink != null && existingMeetLink.isNotEmpty)
                ? existingMeetLink
                : kFallbackMeetLink;
        debugPrint(
          '⚠️ [RoomAllocation] no free rooms — using fallback: $fallback',
        );
        return fallback;
      }

      // 3. Mark the room as in_use for this appointment.
      final now = DateTime.now().toUtc();
      final expiresAt = now.add(kRoomAllocationTtl);
      final updateResult = await client
          .from('meeting_rooms')
          .update({
            'status': 'in_use',
            'appointment_id': appointmentId,
            'doctor_place_id': doctorPlaceId,
            'patient_user_id': patientUserId,
            'allocated_at': now.toIso8601String(),
            'expires_at': expiresAt.toIso8601String(),
          })
          .eq('id', free['id'])
          .eq('status', 'available') // optimistic lock
          .select('id')
          .maybeSingle();

      if (updateResult == null) {
        // Race: another caller grabbed it. Fall back.
        debugPrint(
          '⚠️ [RoomAllocation] allocate race condition — '
          'falling back: ${free['room_url']}',
        );
        return free['room_url'] as String;
      }

      debugPrint(
        '✅ [RoomAllocation] allocated room for $appointmentId: '
        '${free['room_url']}',
      );
      return free['room_url'] as String;
    } catch (e) {
      debugPrint('⚠️ [RoomAllocation] allocate failed (non-fatal): $e');
      // Never block the consultation — fall back to existing link or
      // the hardcoded room.
      return (existingMeetLink != null && existingMeetLink.isNotEmpty)
          ? existingMeetLink
          : kFallbackMeetLink;
    }
  }

  /// Free the room allocated to [appointmentId].
  ///
  /// Called when the doctor marks the appointment Completed or Cancelled.
  /// No-op if the appointment has no room or the room was already freed.
  Future<void> freeRoom(String appointmentId) async {
    try {
      final freeResult = await client
          .from('meeting_rooms')
          .update({
            'status': 'available',
            'appointment_id': null,
            'doctor_place_id': null,
            'patient_user_id': null,
            'allocated_at': null,
            'expires_at': null,
          })
          .eq('appointment_id', appointmentId)
          .eq('status', 'in_use')
          .select('id')
          .maybeSingle();

      if (freeResult != null) {
        debugPrint(
          '✅ [RoomAllocation] freed room for $appointmentId',
        );
      }
    } catch (e) {
      debugPrint('⚠️ [RoomAllocation] free failed (non-fatal): $e');
    }
  }

  /// Release all `in_use` rooms whose `expires_at` has passed.
  ///
  /// Call once on app start and/or periodically. Non-fatal — a failure
  /// simply leaves stale rooms occupied until the next cleanup pass.
  Future<void> cleanupExpiredRooms() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final result = await client
          .from('meeting_rooms')
          .update({
            'status': 'available',
            'appointment_id': null,
            'doctor_place_id': null,
            'patient_user_id': null,
            'allocated_at': null,
            'expires_at': null,
          })
          .lt('expires_at', now)
          .eq('status', 'in_use')
          .select('id');

      final freed = (result as List?)?.length ?? 0;
      if (freed > 0) {
        debugPrint(
          '✅ [RoomAllocation] cleaned up $freed expired room(s)',
        );
      }
    } catch (e) {
      debugPrint('⚠️ [RoomAllocation] cleanup failed (non-fatal): $e');
    }
  }

  /// Check if a specific appointment has an allocated room.
  ///
  /// Returns the room URL if allocated, or null if not.
  Future<String?> getAllocatedRoom(String appointmentId) async {
    try {
      final row = await client
          .from('meeting_rooms')
          .select('room_url')
          .eq('appointment_id', appointmentId)
          .eq('status', 'in_use')
          .maybeSingle();
      return row?['room_url'] as String?;
    } catch (_) {
      return null;
    }
  }
}
