import 'package:flutter_test/flutter_test.dart';
import 'package:ys_mobile/src/services/call_state_machine.dart';

void main() {
  test('rejects late and out-of-order call transitions', () {
    expect(CallStateMachine.canTransition('idle', 'incoming'), isTrue);
    expect(CallStateMachine.canTransition('incoming', 'connecting'), isTrue);
    expect(CallStateMachine.canTransition('connecting', 'active'), isTrue);
    expect(CallStateMachine.canTransition('active', 'idle'), isTrue);
    expect(CallStateMachine.canTransition('idle', 'active'), isFalse);
    expect(CallStateMachine.canTransition('idle', 'connecting'), isFalse);
    expect(CallStateMachine.canTransition('outgoing', 'incoming'), isFalse);
  });
}
