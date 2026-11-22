import 'package:better_together/data/ai_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AiTiming.reset();
    AiTiming.enabled = false;
  });
  test('disabled diagnostics retain no events', () {
    AiTiming.enabled = false;
    AiTiming.selectionStarted('batch', 1);
    AiTiming.mark('photo_queued', batch: 'batch', photo: 'photo');
    AiTiming.selectionEnded('batch');
    expect(AiTiming.events, isEmpty);
  });
  test('early photo completion cannot finish a still populating batch', () {
    AiTiming.enabled = true;
    AiTiming.reset();
    AiTiming.selectionStarted('batch', 2);
    AiTiming.mark('photo_queued', batch: 'batch', photo: 'one');
    AiTiming.mark(
      'photo_terminal',
      batch: 'batch',
      photo: 'one',
      state: 'ready',
    );
    expect(
      AiTiming.events.where((e) => e['event'] == 'batch_terminal'),
      isEmpty,
    );
    AiTiming.mark('photo_queued', batch: 'batch', photo: 'two');
    AiTiming.selectionEnded('batch');
    expect(
      AiTiming.events.where((e) => e['event'] == 'batch_terminal'),
      isEmpty,
    );
    AiTiming.mark(
      'photo_terminal',
      batch: 'batch',
      photo: 'two',
      state: 'pending',
    );
    AiTiming.selectionEnded('batch');
    expect(
      AiTiming.events.where((e) => e['event'] == 'batch_terminal'),
      hasLength(1),
    );
  });
}
