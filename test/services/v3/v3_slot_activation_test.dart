import 'package:flutter_test/flutter_test.dart';
import 'package:gavra_android/services/v3/v3_slot_activation.dart';

void main() {
  group('activateSlotWithRetry', () {
    test('retries and logs error when RPC returns ok=false', () async {
      var notifyCalls = 0;
      var findCalls = 0;
      final logs = <String>[];

      await activateSlotWithRetry(
        vozacId: 'vozac-1',
        datumIso: '2026-08-06',
        grad: 'BC',
        vreme: '14:30',
        log: logs.add,
        findExistingSlot: () async {
          findCalls++;
          return <String, dynamic>{
            'id': 'slot-1',
            'tracking_started_at': null,
          };
        },
        updateSlot: (_, __) async {},
        notifyDriverStarted: () async {
          notifyCalls++;
          return <String, dynamic>{'ok': false, 'reason': 'forced_test_error'};
        },
        sleep: (_) async {},
      );

      expect(findCalls, 3);
      expect(notifyCalls, 3);
      expect(
        logs.any((line) => line.contains('greška nakon 3 pokušaja')),
        isTrue,
      );
    });

    test('logs success on first attempt when RPC is ok', () async {
      final logs = <String>[];

      await activateSlotWithRetry(
        vozacId: 'vozac-1',
        datumIso: '2026-08-06',
        grad: 'BC',
        vreme: '14:30',
        log: logs.add,
        findExistingSlot: () async => <String, dynamic>{
          'id': 'slot-1',
          'tracking_started_at': null,
        },
        updateSlot: (_, __) async {},
        notifyDriverStarted: () async => <String, dynamic>{'ok': true, 'notified': 1},
        sleep: (_) async {},
      );

      expect(
        logs.any((line) => line.contains('✅ activateSlot + notify uspešan')),
        isTrue,
      );
    });
  });
}
