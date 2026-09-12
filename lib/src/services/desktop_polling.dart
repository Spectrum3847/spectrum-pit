Duration pollDelayFor(Duration pollInterval, int consecutiveFailures) {
  if (consecutiveFailures <= 0) return pollInterval;
  final multiplier = 1 << (consecutiveFailures - 1).clamp(0, 4);
  return pollInterval * multiplier;
}
