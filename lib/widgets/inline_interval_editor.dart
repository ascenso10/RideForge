import 'package:flutter/material.dart';
import '../models/workout_models.dart';
import '../models/trainer_capabilities.dart';

/// Inline interval editor - expands in place for editing
class InlineIntervalEditor extends StatefulWidget {
  final WorkoutInterval? interval;
  final int index;
  final bool isExpanded;
  final bool isNew;
  final VoidCallback onTap;
  final Function(WorkoutInterval) onSave;
  final VoidCallback onDelete;
  final VoidCallback? onCancel;
  final TrainerCapabilities? capabilities;

  const InlineIntervalEditor({
    super.key,
    this.interval,
    required this.index,
    required this.isExpanded,
    this.isNew = false,
    required this.onTap,
    required this.onSave,
    required this.onDelete,
    this.onCancel,
    this.capabilities,
  });

  @override
  State<InlineIntervalEditor> createState() => _InlineIntervalEditorState();
}

class _InlineIntervalEditorState extends State<InlineIntervalEditor> {
  late TextEditingController _nameController;
  late IntervalType _type;
  late WorkoutMode _mode;
  late int _minutes;
  late int _seconds;
  late int _power;
  late double _slope;
  late double _resistance;
  late bool _enableRamp;
  late int _startPower;
  late int _endPower;
  late RampType _rampType;

  int get _maxPower => widget.capabilities?.maxPower ?? 600;
  double get _maxSlope => widget.capabilities?.maxGradient ?? 6.0;

  @override
  void initState() {
    super.initState();
    _initializeValues();
  }

  @override
  void didUpdateWidget(InlineIntervalEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) {
      _initializeValues();
    }
  }

  void _initializeValues() {
    final interval = widget.interval;
    _nameController = TextEditingController(text: interval?.name ?? '');
    _type = interval?.type ?? IntervalType.work;
    _mode = interval?.mode ?? WorkoutMode.power;
    _minutes = interval?.duration.inMinutes ?? 5;
    _seconds = (interval?.duration.inSeconds ?? 0) % 60;
    _power = (interval?.targetPower ?? 200).clamp(50, _maxPower);
    _slope = (interval?.targetSlope ?? 0).clamp(0.0, _maxSlope);
    _resistance = interval?.targetResistance ?? 50;
    _enableRamp = interval?.powerRamp != null;
    _startPower = (interval?.powerRamp?.startPower ?? 150).clamp(50, _maxPower);
    _endPower = (interval?.powerRamp?.endPower ?? 250).clamp(50, _maxPower);
    _rampType = interval?.powerRamp?.type ?? RampType.linear;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isExpanded) {
      return _buildCollapsedView();
    }
    return _buildExpandedView();
  }

  Widget _buildCollapsedView() {
    final interval = widget.interval;
    if (interval == null) return const SizedBox();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Drag handle
              Icon(Icons.drag_handle, color: Colors.grey[400], size: 20),
              const SizedBox(width: 8),
              // Type indicator
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _getTypeColor(interval.type),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${widget.index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Interval info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            interval.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (interval.hasRamping)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'RAMP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildInfoChip(
                          Icons.timer,
                          _formatDuration(interval.duration),
                        ),
                        const SizedBox(width: 8),
                        _buildInfoChip(
                          _getModeIcon(interval.mode),
                          _getTargetText(interval),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Edit indicator
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _buildExpandedView() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).primaryColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with collapse button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isNew ? 'New Interval' : 'Edit Interval',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                if (!widget.isNew)
                  IconButton(
                    onPressed: widget.onTap,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    tooltip: 'Collapse',
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name field (optional)
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'Leave blank to auto-name from type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),

                // Type selector (compact chips)
                _buildSectionLabel('Type'),
                const SizedBox(height: 8),
                _buildTypeSelector(),
                const SizedBox(height: 16),

                // Duration row
                _buildSectionLabel('Duration'),
                const SizedBox(height: 8),
                _buildDurationRow(),
                const SizedBox(height: 16),

                // Mode and Target
                _buildSectionLabel('Target'),
                const SizedBox(height: 8),
                _buildModeSelector(),
                const SizedBox(height: 12),
                _buildTargetControl(),

                // Power ramping (only for power mode)
                if (_mode == WorkoutMode.power) ...[
                  const SizedBox(height: 16),
                  _buildRampingSection(),
                ],

                const SizedBox(height: 20),

                // Action buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey[600],
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: IntervalType.values.map((type) {
        final isSelected = _type == type;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: type != IntervalType.cooldown ? 8 : 0,
            ),
            child: _buildSelectableChip(
              label: _getTypeName(type),
              icon: _getTypeIcon(type),
              color: _getTypeColor(type),
              isSelected: isSelected,
              onTap: () => setState(() => _type = type),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSelectableChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: isSelected ? Colors.white : color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationRow() {
    return Column(
      children: [
        Row(
          children: [
            // Minutes
            Expanded(
              child: _buildNumberInput(
                value: _minutes,
                label: 'min',
                onChanged: (v) => setState(() => _minutes = v),
                max: 60,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                ':',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            // Seconds
            Expanded(
              child: _buildNumberInput(
                value: _seconds,
                label: 'sec',
                onChanged: (v) => setState(() => _seconds = v),
                max: 59,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Quick duration buttons below
        Row(
          children: [
            _buildQuickDurationButton('30s', 0, 30),
            const SizedBox(width: 6),
            _buildQuickDurationButton('1m', 1, 0),
            const SizedBox(width: 6),
            _buildQuickDurationButton('5m', 5, 0),
            const SizedBox(width: 6),
            _buildQuickDurationButton('10m', 10, 0),
            const SizedBox(width: 6),
            _buildQuickDurationButton('20m', 20, 0),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickDurationButton(String label, int min, int sec) {
    final isSelected = _minutes == min && _seconds == sec;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _minutes = min;
          _seconds = sec;
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberInput({
    required int value,
    required String label,
    required Function(int) onChanged,
    required int max,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<WorkoutMode>(
        segments: WorkoutMode.values.map((mode) {
          return ButtonSegment(
            value: mode,
            label: Text(
              _getModeName(mode),
              style: const TextStyle(fontSize: 12),
            ),
            icon: Icon(_getModeIcon(mode), size: 18),
          );
        }).toList(),
        selected: {_mode},
        onSelectionChanged: (selection) {
          setState(() {
            _mode = selection.first;
            if (_mode != WorkoutMode.power) {
              _enableRamp = false;
            }
          });
        },
        style: ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }

  Widget _buildTargetControl() {
    switch (_mode) {
      case WorkoutMode.power:
        final maxPower = _maxPower.toDouble();
        final divisions = ((maxPower - 50) / 10).round();
        return _buildSliderWithValue(
          value: _power.toDouble(),
          min: 50,
          max: maxPower,
          divisions: divisions,
          unit: 'W',
          color: Colors.red,
          onChanged: (v) => setState(() => _power = v.toInt()),
          quickValues: [
            100,
            150,
            200,
            250,
            300,
          ].where((v) => v <= maxPower).toList(),
          enabled: !_enableRamp,
        );
      case WorkoutMode.slope:
        final maxSlope = _maxSlope;
        final divisions = (maxSlope / 0.5).round();
        return _buildSliderWithValue(
          value: _slope,
          min: 0,
          max: maxSlope,
          divisions: divisions,
          unit: '%',
          color: Colors.green,
          onChanged: (v) => setState(() => _slope = v),
          quickValues: [0, 3, 5, 8, 10].where((v) => v <= maxSlope).toList(),
          isDouble: true,
        );
      case WorkoutMode.resistance:
        return _buildSliderWithValue(
          value: _resistance,
          min: 0,
          max: 100,
          divisions: 20,
          unit: '%',
          color: Colors.blue,
          onChanged: (v) => setState(() => _resistance = v),
          quickValues: [25, 50, 75, 100],
        );
    }
  }

  Widget _buildSliderWithValue({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required Color color,
    required Function(double) onChanged,
    required List<num> quickValues,
    bool isDouble = false,
    bool enabled = true,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                activeColor: enabled ? color : Colors.grey,
                onChanged: enabled ? onChanged : null,
              ),
            ),
            Container(
              width: 70,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${isDouble ? value.toStringAsFixed(1) : value.toInt()}$unit',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: quickValues.map((qv) {
            final isSelected =
                enabled &&
                (isDouble
                    ? (value - qv.toDouble()).abs() < 0.1
                    : value.toInt() == qv);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  onTap: enabled ? () => onChanged(qv.toDouble()) : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? color : Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$qv$unit',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : Colors.grey[enabled ? 700 : 400],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRampingSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Power Ramping',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Switch(
                value: _enableRamp,
                activeThumbColor: Colors.orange,
                onChanged: (v) {
                  setState(() {
                    if (v) {
                      // Pre-fill end power with current target when enabling
                      _endPower = _power.clamp(50, _maxPower);
                    }
                    _enableRamp = v;
                  });
                },
              ),
            ],
          ),
          if (_enableRamp) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Start',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      _buildCompactNumberInput(
                        value: _startPower,
                        onChanged: (v) => setState(() => _startPower = v),
                        suffix: 'W',
                        max: _maxPower,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward, color: Colors.orange),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'End',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      _buildCompactNumberInput(
                        value: _endPower,
                        onChanged: (v) => setState(() => _endPower = v),
                        suffix: 'W',
                        max: _maxPower,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: RampType.values.map((type) {
                final isSelected = _rampType == type;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: type != RampType.exponential ? 8 : 0,
                    ),
                    child: InkWell(
                      onTap: () => setState(() => _rampType = type),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.orange
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? Colors.orange
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Text(
                          _getRampTypeName(type),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactNumberInput({
    required int value,
    required Function(int) onChanged,
    required String suffix,
    int max = 600,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: value > 50 ? () => onChanged(value - 10) : null,
            icon: const Icon(Icons.remove, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Expanded(
            child: Text(
              '$value$suffix',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 10) : null,
            icon: const Icon(Icons.add, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        if (!widget.isNew) ...[
          IconButton(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline),
            color: Colors.red,
            tooltip: 'Delete',
          ),
          const SizedBox(width: 8),
        ],
        if (widget.isNew && widget.onCancel != null) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _saveInterval,
            icon: const Icon(Icons.check, size: 18),
            label: Text(widget.isNew ? 'Add Interval' : 'Save Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  void _saveInterval() {
    if (_minutes == 0 && _seconds == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Duration must be greater than 0'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final name = _nameController.text.trim().isEmpty
        ? _getDefaultName(_type)
        : _nameController.text.trim();

    PowerRamp? ramp;
    if (_enableRamp && _mode == WorkoutMode.power) {
      ramp = PowerRamp(
        startPower: _startPower,
        endPower: _endPower,
        type: _rampType,
      );
    }

    final interval = WorkoutInterval(
      id:
          widget.interval?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      duration: Duration(minutes: _minutes, seconds: _seconds),
      type: _type,
      mode: _mode,
      targetPower: _mode == WorkoutMode.power ? _power : null,
      targetSlope: _mode == WorkoutMode.slope ? _slope : null,
      targetResistance: _mode == WorkoutMode.resistance ? _resistance : null,
      powerRamp: ramp,
    );

    widget.onSave(interval);
  }

  // Helper methods
  String _formatDuration(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  String _getDefaultName(IntervalType type) {
    switch (type) {
      case IntervalType.warmup:
        return 'Warm-up';
      case IntervalType.work:
        return 'Work';
      case IntervalType.rest:
        return 'Rest';
      case IntervalType.cooldown:
        return 'Cool-down';
    }
  }

  String _getTargetText(WorkoutInterval interval) {
    switch (interval.mode) {
      case WorkoutMode.power:
        if (interval.hasRamping) {
          return '${interval.powerRamp!.startPower}→${interval.powerRamp!.endPower}W';
        }
        return '${interval.targetPower ?? 0}W';
      case WorkoutMode.slope:
        return '${interval.targetSlope?.toStringAsFixed(1) ?? 0}%';
      case WorkoutMode.resistance:
        return '${interval.targetResistance?.toInt() ?? 0}%';
    }
  }

  Color _getTypeColor(IntervalType type) {
    switch (type) {
      case IntervalType.warmup:
        return Colors.green;
      case IntervalType.work:
        return Colors.red;
      case IntervalType.rest:
        return Colors.blue;
      case IntervalType.cooldown:
        return Colors.orange;
    }
  }

  IconData _getTypeIcon(IntervalType type) {
    switch (type) {
      case IntervalType.warmup:
        return Icons.local_fire_department;
      case IntervalType.work:
        return Icons.fitness_center;
      case IntervalType.rest:
        return Icons.pause;
      case IntervalType.cooldown:
        return Icons.ac_unit;
    }
  }

  String _getTypeName(IntervalType type) {
    switch (type) {
      case IntervalType.warmup:
        return 'Warm';
      case IntervalType.work:
        return 'Work';
      case IntervalType.rest:
        return 'Rest';
      case IntervalType.cooldown:
        return 'Cool';
    }
  }

  IconData _getModeIcon(WorkoutMode mode) {
    switch (mode) {
      case WorkoutMode.power:
        return Icons.flash_on;
      case WorkoutMode.slope:
        return Icons.terrain;
      case WorkoutMode.resistance:
        return Icons.fitness_center;
    }
  }

  String _getModeName(WorkoutMode mode) {
    switch (mode) {
      case WorkoutMode.power:
        return 'Power';
      case WorkoutMode.slope:
        return 'Slope';
      case WorkoutMode.resistance:
        return 'Resist';
    }
  }

  String _getRampTypeName(RampType type) {
    switch (type) {
      case RampType.linear:
        return 'Linear';
      case RampType.step:
        return 'Step';
      case RampType.exponential:
        return 'Curve';
    }
  }
}
