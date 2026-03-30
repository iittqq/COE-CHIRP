import 'package:flutter/material.dart';

class TimerButtonData {
  final String title;
  final String subtitle;
  TimerButtonData({required this.title, required this.subtitle});
}

class TimerButtonRow extends StatefulWidget {
  final List<TimerButtonData> buttons;
  final Function(int) onDurationChanged;
  final bool forceClose;

  const TimerButtonRow({
    super.key,
    required this.buttons,
    required this.onDurationChanged,
    this.forceClose = false,
  });

  @override
  State<TimerButtonRow> createState() => _TimerButtonRowState();
}

class _TimerButtonRowState extends State<TimerButtonRow> {
  bool _showInput = false;
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant TimerButtonRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceClose && _showInput) {
      setState(() {
        _showInput = false;
      });
    }
  }

  final TextEditingController _minController = TextEditingController();
  final TextEditingController _secController = TextEditingController();

  void _notifyParent() {
    int seconds = 0;
    if (_showInput) {
      int mins = int.tryParse(_minController.text) ?? 0;
      int secs = int.tryParse(_secController.text) ?? 0;
      seconds = (mins * 60) + secs;
    } else if (_selectedIndex != null) {
      int mins = int.tryParse(widget.buttons[_selectedIndex!].title) ?? 0;
      seconds = mins * 60;
    }
    widget.onDurationChanged(seconds);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(widget.buttons.length, (index) {
            final item = widget.buttons[index];
            final bool isLast = index == widget.buttons.length - 1;
            final bool isSelected = _selectedIndex == index;

            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                fixedSize: const Size(80, 80),
                backgroundColor: isSelected ? Colors.blue : Colors.white,
                foregroundColor: isSelected ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.zero,
              ),
              onPressed: () {
                setState(() {
                  _selectedIndex = index;
                  _showInput = isLast;
                });
                _notifyParent();
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white70 : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        if (_showInput) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildTimeField(_minController, 'Minutes')),
              const SizedBox(width: 16),
              Expanded(child: _buildTimeField(_secController, 'Seconds')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTimeField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: (_) => _notifyParent(),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
