import 'package:flutter/material.dart';
import '../utils/acquisition.dart';

/// Shows and edits the acquisition settings stored with a scan.
class AcquisitionCard extends StatelessWidget {
  final Map<String, dynamic> acquisition;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const AcquisitionCard({
    super.key,
    required this.acquisition,
    required this.onSave,
  });

  static String _rawText(dynamic v) {
    if (v == null) return '';
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  Future<void> _edit(BuildContext context) async {
    final controllers = {
      for (final f in acquisitionFields)
        f.key: TextEditingController(text: _rawText(acquisition[f.key])),
    };
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Acquisition settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in acquisitionFields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[f.key],
                    keyboardType: f.numeric
                        ? const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          )
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: f.label,
                      helperText: f.help,
                      helperMaxLines: 2,
                      suffixText: f.unit,
                      isDense: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              for (final e in controllers.entries) e.key: e.value.text,
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    if (result != null) await onSave(normalizeAcquisition(result));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Acquisition settings',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: () => _edit(context),
                child: const Text('Edit'),
              ),
            ],
          ),
          for (final f in acquisitionFields)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    f.label,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      formatAcquisitionValue(acquisition, f),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
