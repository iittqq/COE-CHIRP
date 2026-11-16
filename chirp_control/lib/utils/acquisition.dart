// Acquisition settings stored with each scan (in the scan folder's
// metadata.json under "acquisition"). Same keys and meanings as the web app's
// src/utils/acquisition.ts and the backend's ChirpScans `acquisition` map; see
// docs/data-dictionary.md.

class AcquisitionField {
  final String key;
  final String label;
  final bool numeric;
  final String? unit;
  final String? help;
  const AcquisitionField(
    this.key,
    this.label, {
    this.numeric = false,
    this.unit,
    this.help,
  });
}

const acquisitionFields = <AcquisitionField>[
  AcquisitionField('sonarModel', 'Sonar model', help: 'e.g. Deeper CHIRP+ 2'),
  AcquisitionField('sonarFirmware', 'Sonar firmware'),
  AcquisitionField('companionAppVersion', 'Companion app version'),
  AcquisitionField('frequencyMode', 'Frequency / beam mode'),
  AcquisitionField('scanAngleDeg', 'Scan angle', numeric: true, unit: '°'),
  AcquisitionField(
    'transducerElevationM',
    'Transducer elevation',
    numeric: true,
    unit: 'm',
    help: 'Transducer face (lowered position) relative to the datum',
  ),
  AcquisitionField('datum', 'Vertical datum', help: 'e.g. NAVD88 (GEOID18)'),
  AcquisitionField(
    'mountingHeightM',
    'Mounting height',
    numeric: true,
    unit: 'm',
    help: 'Transducer face above the settlement plate / original ground',
  ),
  AcquisitionField(
    'blindSpotOffsetCm',
    'Blind-spot offset',
    numeric: true,
    unit: 'cm',
    help: 'Added to every reported depth. Leave empty for no correction.',
  ),
];

/// Drops unknown keys and blank values; parses numeric fields.
Map<String, dynamic> normalizeAcquisition(dynamic raw) {
  final out = <String, dynamic>{};
  if (raw is! Map) return out;
  for (final f in acquisitionFields) {
    final value = raw[f.key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isEmpty) continue;
    if (f.numeric) {
      final n = value is num ? value.toDouble() : double.tryParse(text);
      if (n != null && n.isFinite) out[f.key] = n;
    } else {
      out[f.key] = text;
    }
  }
  return out;
}

double? acquisitionNumber(Map<String, dynamic> acq, String key) {
  final v = acq[key];
  return v is num ? v.toDouble() : null;
}

String formatAcquisitionValue(Map<String, dynamic> acq, AcquisitionField f) {
  final v = acq[f.key];
  if (v == null || v.toString().isEmpty) {
    return f.key == 'blindSpotOffsetCm' ? 'none applied' : 'not recorded';
  }
  final text = v is double && v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toString();
  return f.unit != null ? '$text ${f.unit}' : text;
}
