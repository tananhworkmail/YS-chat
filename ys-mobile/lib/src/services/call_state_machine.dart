class CallStateMachine {
  static const Map<String, Set<String>> _transitions = {
    'idle': {'incoming', 'outgoing'},
    'incoming': {'connecting', 'idle'},
    'outgoing': {'connecting', 'idle'},
    'connecting': {'active', 'idle'},
    'active': {'idle'},
  };

  static bool canTransition(String current, String next) {
    return current == next || (_transitions[current]?.contains(next) ?? false);
  }
}
