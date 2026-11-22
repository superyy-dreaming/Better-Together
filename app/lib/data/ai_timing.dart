import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Opt-in diagnostic metadata only. Never accepts URLs, headers, image bytes,
/// model output, account names, credentials or free-form exception messages.
class AiTiming {
  static bool enabled = const bool.fromEnvironment('AI_TIMING');
  static final Stopwatch _clock = Stopwatch()..start();
  static final List<Map<String, Object?>> events = [];
  static final Set<String> _seen = {};
  static final Map<String, Set<String>> _pending = {};
  static final Set<String> _selecting = {};
  static final Set<String> _completed = {};

  static void selectionStarted(String batch, int count) {
    if (!enabled) return;
    _selecting.add(batch);
    _completed.remove(batch);
    mark('picker_returned', batch: batch, count: count);
  }

  static void selectionEnded(String batch) {
    if (!enabled) return;
    _selecting.remove(batch);
    mark('originals_ready', batch: batch);
    _completeBatch(batch);
  }

  static void _completeBatch(String batch) {
    if (!_selecting.contains(batch) &&
        _pending.containsKey(batch) &&
        _pending[batch]!.isEmpty &&
        _completed.add(batch)) {
      mark('batch_terminal', batch: batch);
    }
  }

  static void reset() {
    events.clear();
    _seen.clear();
    _pending.clear();
    _selecting.clear();
    _completed.clear();
    _clock.reset();
  }

  static void mark(
    String event, {
    String? batch,
    String? photo,
    String? state,
    int? bytes,
    int? count,
    int? status,
    num? durationMs,
    bool once = false,
  }) {
    if (!enabled) return;
    if (once && !_seen.add('$event|$batch|$photo|$state')) return;
    final row = <String, Object?>{
      'event': event,
      'elapsed_ms': _clock.elapsedMicroseconds / 1000,
      'batch': ?batch,
      'photo': ?photo,
      'state': ?state,
      'bytes': ?bytes,
      'count': ?count,
      'status': ?status,
      'duration_ms': ?durationMs,
    };
    events.add(row);
    debugPrint('BT_AI_TIMING ${jsonEncode(row)}');
    if (batch != null && photo != null) {
      if (event == 'photo_queued') {
        _pending.putIfAbsent(batch, () => {}).add(photo);
      } else if (event == 'photo_terminal') {
        _pending[batch]?.remove(photo);
        _completeBatch(batch);
      }
    }
  }
}
