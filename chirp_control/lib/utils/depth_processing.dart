// Bathymetry processing for the mobile app. This is a line-for-line port of
// chirp-control-web/src/utils/bathymetry.ts so both apps report the same
// numbers for the same scan; both are tested against the shared fixtures in
// test-fixtures/bathymetry/. The rules are documented in the root README
// ("Data processing") and docs/data-dictionary.md - keep all four in sync.

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Schema
// ---------------------------------------------------------------------------

enum BathymetryField { latitude, longitude, depth, temperature, time }

/// Column order of headerless Deeper exports, as it appears in the files.
/// The README the vendor ships inside each export lists column 3 as the
/// timestamp and column 4 as temperature; the files have them the other way
/// round, so this follows the data.
const headerlessColumnOrder = [
  BathymetryField.latitude,
  BathymetryField.longitude,
  BathymetryField.depth,
  BathymetryField.temperature,
  BathymetryField.time,
];

const _headerAliases = <BathymetryField, List<String>>{
  BathymetryField.latitude: ['latitude', 'lat', 'latitudedeg'],
  BathymetryField.longitude: [
    'longitude',
    'longtitude',
    'lon',
    'lng',
    'longitudedeg',
  ],
  BathymetryField.depth: ['depth', 'depthm'],
  BathymetryField.temperature: ['temperature', 'temp', 'temperaturec'],
  BathymetryField.time: [
    'time',
    'timestamp',
    'timems',
    'timestampms',
    'timeunixms',
  ],
};

const _requiredFields = [BathymetryField.depth, BathymetryField.time];

const _minEpochMs = 1000000000000.0; // 2001-09-09 UTC
const _maxEpochMs = 10000000000000.0; // 2286-11-20 UTC
const _maxDepthM = 1000.0;

class BathymetryFormatException implements Exception {
  final String message;
  BathymetryFormatException(this.message);
  @override
  String toString() => message;
}

String _normalizeHeader(String cell) => cell
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

double? _toNumber(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.isFinite ? value.toDouble() : null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  return (parsed != null && parsed.isFinite) ? parsed : null;
}

bool _isHeaderRow(List<dynamic> row) => row.any((cell) {
  if (cell is num) return false;
  final text = cell?.toString().trim() ?? '';
  return text.isNotEmpty && _toNumber(text) == null;
});

bool _looksLikeEpochMs(double? v) =>
    v != null && v >= _minEpochMs && v <= _maxEpochMs;

class BathymetrySample {
  final double timeMs; // Unix epoch milliseconds (UTC)
  final double depthM; // metres below the transducer face, as reported
  final double? temperatureC;
  final double? latitude; // null when there is no GPS fix (0,0 or blank)
  final double? longitude;

  const BathymetrySample({
    required this.timeMs,
    required this.depthM,
    this.temperatureC,
    this.latitude,
    this.longitude,
  });
}

class ParsedBathymetry {
  final List<BathymetrySample> samples; // file order
  final bool hasHeader;
  final int totalRows;
  final int incompleteRows;

  const ParsedBathymetry(
    this.samples,
    this.hasHeader,
    this.totalRows,
    this.incompleteRows,
  );
}

Map<BathymetryField, int> _columnMapFromHeader(List<dynamic> header) {
  final normalized = header.map((c) => _normalizeHeader('$c')).toList();
  final map = <BathymetryField, int>{};
  _headerAliases.forEach((field, aliases) {
    final index = normalized.indexWhere(aliases.contains);
    if (index != -1) map[field] = index;
  });
  final missing = _requiredFields.where((f) => !map.containsKey(f)).toList();
  if (missing.isNotEmpty) {
    throw BathymetryFormatException(
      'bathymetry.csv header is missing required column(s): '
      '${missing.map((f) => f.name).join(', ')}. Found: ${header.join(', ')}.',
    );
  }
  return map;
}

Map<BathymetryField, int> _positionalColumnMap(List<List<dynamic>> dataRows) {
  final map = {
    for (var i = 0; i < headerlessColumnOrder.length; i++)
      headerlessColumnOrder[i]: i,
  };
  for (final row in dataRows) {
    if (row.length < headerlessColumnOrder.length) continue;
    final time = _toNumber(row[map[BathymetryField.time]!]);
    if (time == null) continue;
    if (_looksLikeEpochMs(time)) break;
    if (_looksLikeEpochMs(_toNumber(row[map[BathymetryField.temperature]!]))) {
      throw BathymetryFormatException(
        'bathymetry.csv has its timestamp in column 4 and temperature in column 5. '
        'This app expects latitude, longitude, depth (m), temperature (°C), time (Unix ms). '
        'Add a header row (latitude,longitude,depth,temperature,time) to import this file.',
      );
    }
    throw BathymetryFormatException(
      'bathymetry.csv column 5 (${_fmt(time)}) is not a Unix timestamp in milliseconds. '
      'The vendor export format may have changed; see docs/data-dictionary.md.',
    );
  }
  return map;
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Parses by header name when the file has a header row and by the documented
/// column order when it doesn't. Throws [BathymetryFormatException] when the
/// file matches neither.
ParsedBathymetry parseBathymetryRows(List<List<dynamic>> rows) {
  final nonEmpty = rows
      .where((row) => row.any((c) => (c?.toString().trim() ?? '').isNotEmpty))
      .where(
        (row) => !(row.first?.toString().trimLeft().startsWith('#') ?? false),
      )
      .toList();
  if (nonEmpty.isEmpty) return const ParsedBathymetry([], false, 0, 0);

  final hasHeader = _isHeaderRow(nonEmpty.first);
  final dataRows = hasHeader ? nonEmpty.sublist(1) : nonEmpty;
  final map = hasHeader
      ? _columnMapFromHeader(nonEmpty.first)
      : _positionalColumnMap(dataRows);

  dynamic cell(List<dynamic> row, BathymetryField f) {
    final i = map[f];
    return (i == null || i >= row.length) ? null : row[i];
  }

  final samples = <BathymetrySample>[];
  var incomplete = 0;
  for (final row in dataRows) {
    final depthM = _toNumber(cell(row, BathymetryField.depth));
    final timeMs = _toNumber(cell(row, BathymetryField.time));
    if (depthM == null || timeMs == null) {
      incomplete++;
      continue;
    }
    if (!_looksLikeEpochMs(timeMs)) {
      throw BathymetryFormatException(
        'bathymetry.csv has a time value (${_fmt(timeMs)}) that is not a Unix timestamp in milliseconds.',
      );
    }
    if (depthM < 0 || depthM > _maxDepthM) {
      throw BathymetryFormatException(
        'bathymetry.csv has a depth of $depthM, which is not a plausible depth in metres.',
      );
    }
    final lat = _toNumber(cell(row, BathymetryField.latitude));
    final lon = _toNumber(cell(row, BathymetryField.longitude));
    final hasFix = lat != null && lon != null && !(lat == 0 && lon == 0);
    samples.add(
      BathymetrySample(
        timeMs: timeMs,
        depthM: depthM,
        temperatureC: _toNumber(cell(row, BathymetryField.temperature)),
        latitude: hasFix ? lat : null,
        longitude: hasFix ? lon : null,
      ),
    );
  }
  return ParsedBathymetry(samples, hasHeader, dataRows.length, incomplete);
}

// ---------------------------------------------------------------------------
// Cleaning: time-island trimming (see README "Cleaning")
// ---------------------------------------------------------------------------

const islandGapMedianMultiple = 20.0;
const islandGapSpanFraction = 0.15;
const islandMaxFraction = 0.15;
const islandMinSamples = 10;

class TrimResult<T> {
  final List<T> kept;
  final int droppedLeading;
  final int droppedTrailing;
  const TrimResult(this.kept, this.droppedLeading, this.droppedTrailing);
}

TrimResult<T> trimOutlyingTimeIslands<T>(
  List<T> sorted,
  double Function(T) timeOf,
) {
  final untouched = TrimResult<T>(sorted, 0, 0);
  final n = sorted.length;
  if (n < islandMinSamples) return untouched;

  final totalSpan = timeOf(sorted.last) - timeOf(sorted.first);
  if (totalSpan <= 0) return untouched;

  final deltas = <double>[
    for (var i = 1; i < n; i++) timeOf(sorted[i]) - timeOf(sorted[i - 1]),
  ];
  final sortedDeltas = [...deltas]..sort();
  final median = sortedDeltas[sortedDeltas.length ~/ 2];
  final gapThreshold = math.max(
    median * islandGapMedianMultiple,
    totalSpan * islandGapSpanFraction,
  );

  var start = 0;
  var end = n;
  for (var i = 1; i < n; i++) {
    if (i / n > islandMaxFraction) break;
    if (deltas[i - 1] >= gapThreshold) start = i;
  }
  for (var i = n - 1; i >= 1; i--) {
    if ((n - i) / n > islandMaxFraction) break;
    if (deltas[i - 1] >= gapThreshold) end = i;
  }
  if (end - start < 2) return untouched;
  return TrimResult<T>(sorted.sublist(start, end), start, n - end);
}

// ---------------------------------------------------------------------------
// Processed scan and derived quantities
// ---------------------------------------------------------------------------

class ProcessingCounts {
  final int totalRows;
  final int incompleteRows;
  final int droppedLeading;
  final int droppedTrailing;
  final int used;
  const ProcessingCounts({
    required this.totalRows,
    required this.incompleteRows,
    required this.droppedLeading,
    required this.droppedTrailing,
    required this.used,
  });
}

class ProcessedScan {
  final List<BathymetrySample> samples; // time-sorted, trimmed
  final double? startMs;
  final double? endMs;
  final double blindSpotOffsetCm;
  final ProcessingCounts counts;
  const ProcessedScan({
    required this.samples,
    required this.startMs,
    required this.endMs,
    required this.blindSpotOffsetCm,
    required this.counts,
  });

  /// Depth in cm below the transducer face, with the blind-spot offset.
  double depthCm(BathymetrySample s) => s.depthM * 100 + blindSpotOffsetCm;
}

ProcessedScan processBathymetry(
  List<List<dynamic>> rows, {
  double? blindSpotOffsetCm,
}) {
  final parsed = parseBathymetryRows(rows);
  final sorted = [...parsed.samples]
    ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final trim = trimOutlyingTimeIslands<BathymetrySample>(
    sorted,
    (s) => s.timeMs,
  );
  final samples = trim.kept;
  return ProcessedScan(
    samples: samples,
    startMs: samples.isEmpty ? null : samples.first.timeMs,
    endMs: samples.isEmpty ? null : samples.last.timeMs,
    blindSpotOffsetCm: blindSpotOffsetCm ?? 0,
    counts: ProcessingCounts(
      totalRows: parsed.totalRows,
      incompleteRows: parsed.incompleteRows,
      droppedLeading: trim.droppedLeading,
      droppedTrailing: trim.droppedTrailing,
      used: samples.length,
    ),
  );
}

/// Never throws; returns the format error message instead.
({ProcessedScan? scan, String? error}) tryProcessBathymetry(
  List<List<dynamic>> rows, {
  double? blindSpotOffsetCm,
}) {
  try {
    return (
      scan: processBathymetry(rows, blindSpotOffsetCm: blindSpotOffsetCm),
      error: null,
    );
  } on BathymetryFormatException catch (e) {
    return (scan: null, error: e.message);
  }
}

class DepthStatistics {
  final double avgCm;
  final double minCm;
  final double maxCm;
  final double? stdCm; // sample SD (n - 1); null when n < 2
  final int n;
  const DepthStatistics(this.avgCm, this.minCm, this.maxCm, this.stdCm, this.n);
}

DepthStatistics? depthStatistics(ProcessedScan scan) {
  final values = scan.samples.map(scan.depthCm).toList();
  final n = values.length;
  if (n == 0) return null;
  final mean = values.reduce((a, b) => a + b) / n;
  final variance = n > 1
      ? values.fold<double>(0, (a, v) => a + (v - mean) * (v - mean)) / (n - 1)
      : null;
  return DepthStatistics(
    mean,
    values.reduce(math.min),
    values.reduce(math.max),
    variance == null ? null : math.sqrt(variance),
    n,
  );
}

/// Settled depth = mean depth over the final [settledWindowS] seconds of the
/// scan, by timestamp, after trimming.
const settledWindowS = 30;

class SettledDepth {
  final double depthCm;
  final int n;
  final int windowS;
  const SettledDepth(this.depthCm, this.n, this.windowS);
}

SettledDepth? settledDepth(ProcessedScan scan, {int windowS = settledWindowS}) {
  final end = scan.endMs;
  if (end == null) return null;
  final cutoff = end - windowS * 1000;
  final values = scan.samples
      .where((s) => s.timeMs >= cutoff)
      .map(scan.depthCm)
      .toList();
  if (values.isEmpty) return null;
  return SettledDepth(
    values.reduce((a, b) => a + b) / values.length,
    values.length,
    windowS,
  );
}

class DepthChange {
  final double changeCm; // settled(latest) - settled(earliest)
  final int earliestIndex;
  final int latestIndex;
  const DepthChange(this.changeCm, this.earliestIndex, this.latestIndex);
}

/// Signed change from the chronologically earliest scan to the latest one.
/// Negative = depth decreased = mudline rose toward the sonar.
DepthChange? depthChange(List<ProcessedScan> scans) {
  final candidates = <({int index, double start, double settled})>[];
  for (var i = 0; i < scans.length; i++) {
    final start = scans[i].startMs;
    final settled = settledDepth(scans[i]);
    if (start == null || settled == null) continue;
    candidates.add((index: i, start: start, settled: settled.depthCm));
  }
  if (candidates.length < 2) return null;
  candidates.sort((a, b) => a.start.compareTo(b.start));
  final earliest = candidates.first;
  final latest = candidates.last;
  return DepthChange(
    latest.settled - earliest.settled,
    earliest.index,
    latest.index,
  );
}

String describeDepthChange(double changeCm) {
  if (changeCm.abs() < 0.005) return 'no change';
  return changeCm < 0 ? 'mudline rose' : 'mudline fell';
}

/// Mudline elevation relative to the datum: transducer elevation - depth.
double? mudlineElevationM(double? transducerElevationM, double? depthCm) {
  if (transducerElevationM == null || depthCm == null) return null;
  return transducerElevationM - depthCm / 100;
}

String processingSummary(ProcessingCounts c) {
  final trimmed = c.droppedLeading + c.droppedTrailing;
  final parts = ['${c.used} of ${c.totalRows} rows used'];
  if (c.incompleteRows > 0) {
    parts.add('${c.incompleteRows} missing depth or time');
  }
  if (trimmed > 0) {
    parts.add(
      '$trimmed removed as isolated time islands '
      '(${c.droppedLeading} leading, ${c.droppedTrailing} trailing)',
    );
  }
  return parts.join('; ');
}

/// Chart points: x = seconds since the first used sample, y = depth in cm
/// (callers convert units and negate for display).
List<({double seconds, double depthCm})> depthSeries(ProcessedScan scan) {
  final start = scan.startMs;
  if (start == null) return const [];
  return [
    for (final s in scan.samples)
      (seconds: (s.timeMs - start) / 1000.0, depthCm: scan.depthCm(s)),
  ];
}
