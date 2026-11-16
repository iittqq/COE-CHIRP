// Tests the mobile depth processing against the fixtures shared with the web
// app (test-fixtures/bathymetry/, regenerate with generate.py there), so both
// apps are held to the same expected numbers.

import 'dart:convert';
import 'dart:io';

import 'package:chirp_control/utils/depth_processing.dart';
import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

final _dir = '${Directory.current.path}/../test-fixtures/bathymetry';

List<List<dynamic>> rows(String name) =>
    const CsvDecoder().convert(File('$_dir/$name').readAsStringSync());

final Map<String, dynamic> expected = jsonDecode(
  File('$_dir/expected.json').readAsStringSync(),
);

void checkAgainst(ProcessedScan scan, Map<String, dynamic> exp) {
  expect(scan.counts.totalRows, exp['totalRows']);
  expect(scan.counts.incompleteRows, exp['incompleteRows']);
  expect(scan.counts.droppedLeading, exp['droppedLeading']);
  expect(scan.counts.droppedTrailing, exp['droppedTrailing']);
  expect(scan.counts.used, exp['used']);
  expect(scan.startMs, (exp['startMs'] as num).toDouble());
  expect(scan.endMs, (exp['endMs'] as num).toDouble());

  final stats = depthStatistics(scan)!;
  expect(stats.n, exp['used']);
  expect(stats.avgCm, closeTo(exp['avgCm'], 1e-9));
  expect(stats.stdCm!, closeTo(exp['sdCm'], 1e-9));
  expect(stats.minCm, closeTo(exp['minCm'], 1e-9));
  expect(stats.maxCm, closeTo(exp['maxCm'], 1e-9));

  final settled = settledDepth(scan)!;
  expect(settled.depthCm, closeTo(exp['settledCm'], 1e-9));
  expect(settled.n, exp['settledN']);
}

void main() {
  test('uses the shared settled window', () {
    expect(settledWindowS, expected['settledWindowS']);
  });

  final files = expected['files'] as Map<String, dynamic>;
  for (final name in files.keys) {
    test('processes $name as documented', () {
      checkAgainst(processBathymetry(rows(name)), files[name]);
    });
  }

  test('applies the blind-spot offset to every statistic', () {
    checkAgainst(
      processBathymetry(rows('headerless.csv'), blindSpotOffsetCm: 5),
      files['headerless.csv']['blindSpotOffset5'],
    );
  });

  test("reads a header row by name, including 'longtitude'", () {
    final parsed = parseBathymetryRows(rows('header.csv'));
    expect(parsed.hasHeader, isTrue);
    expect(parsed.samples.first.latitude, isNull);
    expect(parsed.samples.first.temperatureC, 23);
  });

  final errors = expected['errors'] as Map<String, dynamic>;
  for (final entry in errors.entries) {
    test('rejects ${entry.key}', () {
      expect(
        () => parseBathymetryRows(rows(entry.key)),
        throwsA(
          isA<BathymetryFormatException>().having(
            (e) => e.message,
            'message',
            contains(entry.value as String),
          ),
        ),
      );
    });
  }

  test('signs the depth change from the earliest to the latest scan', () {
    final change = expected['depthChange'] as Map<String, dynamic>;
    final inputs = (change['inputs'] as List).cast<String>();
    final scans = inputs.map((n) => processBathymetry(rows(n))).toList();
    final result = depthChange(scans)!;
    expect(result.changeCm, closeTo(change['changeCm'], 1e-9));
    expect(inputs[result.earliestIndex], change['earliest']);
    expect(inputs[result.latestIndex], change['latest']);
    expect(
      depthChange(scans.reversed.toList())!.changeCm,
      closeTo(change['changeCm'], 1e-9),
    );
    expect(describeDepthChange(result.changeCm), 'mudline rose');
  });

  test('needs two scans for a depth change', () {
    expect(depthChange([processBathymetry(rows('headerless.csv'))]), isNull);
  });

  test('empty input gives no statistics', () {
    expect(depthStatistics(processBathymetry(const [])), isNull);
  });

  test('mudline elevation = transducer elevation - depth', () {
    expect(mudlineElevationM(1.5, 50), closeTo(1.0, 1e-12));
    expect(mudlineElevationM(null, 50), isNull);
  });
}
