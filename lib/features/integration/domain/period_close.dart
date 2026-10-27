class PeriodReview {
  const PeriodReview({
    required this.period,
    required this.revision,
    required this.closed,
    required this.token,
    required this.issues,
    required this.history,
  });
  final String period, token;
  final int revision;
  final bool closed;
  final List<String> issues;
  final List<Map<String, Object?>> history;
}

abstract interface class PeriodCloseStore {
  Future<PeriodReview> review(String farm, String period);
  Future<void> close(
    String farm,
    String period,
    String token,
    int revision,
    String reason,
    String actor,
    void Function() authorize,
  );
  Future<void> reopen(
    String farm,
    String period,
    int revision,
    String reason,
    String actor,
    void Function() authorize,
  );
}
