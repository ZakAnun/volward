class _ScanProgressBand {
  const _ScanProgressBand({
    required this.start,
    required this.end,
    required this.duration,
  });

  final double start;
  final double end;
  final Duration duration;
}

_ScanProgressBand _scanProgressBandFor(String? phase) {
  return switch (phase) {
    'DiscoveringRoots' => const _ScanProgressBand(
      start: 0.0,
      end: 0.04,
      duration: Duration(seconds: 2),
    ),
    'Walking' => const _ScanProgressBand(
      start: 0.04,
      end: 0.86,
      duration: Duration(minutes: 4),
    ),
    'Classifying' => const _ScanProgressBand(
      start: 0.86,
      end: 0.93,
      duration: Duration(seconds: 25),
    ),
    'Aggregating' => const _ScanProgressBand(
      start: 0.93,
      end: 0.97,
      duration: Duration(seconds: 15),
    ),
    'SavingResults' => const _ScanProgressBand(
      start: 0.97,
      end: 0.99,
      duration: Duration(seconds: 8),
    ),
    'LoadingResults' => const _ScanProgressBand(
      start: 0.99,
      end: 0.995,
      duration: Duration(seconds: 4),
    ),
    _ => const _ScanProgressBand(
      start: 0.0,
      end: 0.99,
      duration: Duration(minutes: 4),
    ),
  };
}

double? estimateScanFraction({
  required bool scanning,
  required String? phase,
  required DateTime? scanStartedAt,
  required DateTime now,
}) {
  if (!scanning) return null;
  if (phase == 'Done') return 1.0;

  final startedAt = scanStartedAt;
  if (startedAt == null) return 0.0;

  final band = _scanProgressBandFor(phase);
  final elapsedMs = now.difference(startedAt).inMilliseconds;
  final phaseProgress = elapsedMs <= 0
      ? 0.0
      : elapsedMs / (elapsedMs + band.duration.inMilliseconds);
  final estimated = band.start + (band.end - band.start) * phaseProgress;
  return estimated.clamp(0.0, 0.99).toDouble();
}
