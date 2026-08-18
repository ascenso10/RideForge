import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/workout_models.dart';
import '../services/workout_service.dart';
import '../widgets/inline_interval_editor.dart';

class WorkoutBuilderScreen extends StatefulWidget {
  final Workout? editingWorkout;

  const WorkoutBuilderScreen({super.key, this.editingWorkout});

  @override
  State<WorkoutBuilderScreen> createState() => _WorkoutBuilderScreenState();
}

class _WorkoutBuilderScreenState extends State<WorkoutBuilderScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<WorkoutInterval> _intervals = [];
  final ScrollController _scrollController = ScrollController();
  bool _isSaving = false;
  int? _expandedIndex;
  bool _isAddingNew = false;

  @override
  void initState() {
    super.initState();
    if (widget.editingWorkout != null) {
      _loadExistingWorkout();
    } else {
      _addDefaultWarmup();
    }
  }

  void _loadExistingWorkout() {
    final workout = widget.editingWorkout!;
    _nameController.text = workout.name;
    _descriptionController.text = workout.description;
    _intervals.addAll(workout.intervals);
  }

  void _addDefaultWarmup() {
    _intervals.add(
      WorkoutInterval(
        id: '1',
        name: 'Warm-up',
        duration: const Duration(minutes: 10),
        type: IntervalType.warmup,
        mode: WorkoutMode.power,
        targetPower: 100,
        description: 'Easy spinning to warm up',
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isEditing => _expandedIndex != null || _isAddingNew;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isEditing
          ? null
          : AppBar(
              title: Text(
                widget.editingWorkout != null
                    ? 'Edit Workout'
                    : 'Build Workout',
              ),
              actions: [
                if (widget.editingWorkout != null)
                  IconButton(
                    onPressed: _deleteWorkout,
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete Workout',
                  ),
                IconButton(
                  onPressed: _isSaving ? null : _saveWorkout,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  tooltip: 'Save',
                ),
              ],
            ),
      body: Column(
        children: [
          // Workout header — hidden while editing an interval
          if (!_isEditing) _buildWorkoutHeader(),

          // Intervals list
          Expanded(child: _buildIntervalsList()),

          // Add interval button (fixed at bottom)
          if (!_isAddingNew) _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildWorkoutHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Workout name and description
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Workout Name',
              hintText: 'e.g., Hill Intervals',
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
          const SizedBox(height: 12),

          // Stats row
          _buildWorkoutStats(),
        ],
      ),
    );
  }

  Widget _buildWorkoutStats() {
    final totalDuration = _intervals.fold(
      Duration.zero,
      (total, interval) => total + interval.duration,
    );

    final powerIntervals = _intervals.where(
      (i) => i.mode == WorkoutMode.power && i.targetPower != null,
    );
    final avgPower = powerIntervals.isNotEmpty
        ? powerIntervals.map((i) => i.targetPower!).reduce((a, b) => a + b) /
              powerIntervals.length
        : 0.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatChip(Icons.timer, '${totalDuration.inMinutes}m', 'Duration'),
        _buildStatChip(Icons.timeline, '${_intervals.length}', 'Intervals'),
        _buildStatChip(Icons.bolt, '${avgPower.toInt()}W', 'Avg Power'),
      ],
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.blue),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntervalsList() {
    return ReorderableListView.builder(
      scrollController: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _intervals.length + (_isAddingNew ? 1 : 0),
      onReorder: _reorderIntervals,
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final capabilities = context.read<WorkoutService>().trainerCapabilities;
        // New interval form at the end
        if (_isAddingNew && index == _intervals.length) {
          return InlineIntervalEditor(
            key: const ValueKey('new_interval'),
            index: index,
            isExpanded: true,
            isNew: true,
            capabilities: capabilities,
            onTap: () {},
            onSave: (interval) {
              setState(() {
                _intervals.add(interval);
                _isAddingNew = false;
              });
            },
            onDelete: () {},
            onCancel: () {
              setState(() {
                _isAddingNew = false;
              });
            },
          );
        }

        final interval = _intervals[index];
        return InlineIntervalEditor(
          key: ValueKey(interval.id),
          interval: interval,
          index: index,
          isExpanded: _expandedIndex == index,
          capabilities: capabilities,
          onTap: () {
            setState(() {
              if (_expandedIndex == index) {
                _expandedIndex = null;
              } else {
                _expandedIndex = index;
                _isAddingNew = false;
              }
            });
          },
          onSave: (updatedInterval) {
            setState(() {
              _intervals[index] = updatedInterval;
              _expandedIndex = null;
            });
          },
          onDelete: () => _deleteInterval(index),
        );
      },
    );
  }

  Widget _buildAddButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Quick add buttons
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _quickAddInterval(IntervalType.work),
              icon: Icon(Icons.fitness_center, color: Colors.red, size: 18),
              label: const Text('Work'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _quickAddInterval(IntervalType.rest),
              icon: Icon(Icons.pause, color: Colors.blue, size: 18),
              label: const Text('Rest'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: const BorderSide(color: Colors.blue),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Custom add button
          ElevatedButton.icon(
            onPressed: _startAddingInterval,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Custom'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _quickAddInterval(IntervalType type) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final interval = WorkoutInterval(
      id: id,
      name: type == IntervalType.work ? 'Work' : 'Recovery',
      duration: Duration(minutes: type == IntervalType.work ? 5 : 2),
      type: type,
      mode: WorkoutMode.power,
      targetPower: type == IntervalType.work ? 200 : 100,
    );

    setState(() {
      _intervals.add(interval);
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _startAddingInterval() {
    setState(() {
      _isAddingNew = true;
      _expandedIndex = null;
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _deleteInterval(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Interval'),
        content: Text('Delete "${_intervals[index].name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _intervals.removeAt(index);
                if (_expandedIndex == index) {
                  _expandedIndex = null;
                } else if (_expandedIndex != null && _expandedIndex! > index) {
                  _expandedIndex = _expandedIndex! - 1;
                }
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _reorderIntervals(int oldIndex, int newIndex) {
    // Don't reorder if we're adding a new interval
    if (_isAddingNew &&
        (oldIndex == _intervals.length || newIndex == _intervals.length + 1)) {
      return;
    }

    setState(() {
      if (newIndex > oldIndex) {
        newIndex--;
      }
      final interval = _intervals.removeAt(oldIndex);
      _intervals.insert(newIndex, interval);

      // Update expanded index
      if (_expandedIndex == oldIndex) {
        _expandedIndex = newIndex;
      } else if (_expandedIndex != null) {
        if (oldIndex < _expandedIndex! && newIndex >= _expandedIndex!) {
          _expandedIndex = _expandedIndex! - 1;
        } else if (oldIndex > _expandedIndex! && newIndex <= _expandedIndex!) {
          _expandedIndex = _expandedIndex! + 1;
        }
      }
    });
  }

  Future<void> _saveWorkout() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a workout name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_intervals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one interval'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final workout = Workout(
        id:
            widget.editingWorkout?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? 'Custom workout'
            : _descriptionController.text.trim(),
        intervals: _intervals,
      );

      final workoutService = context.read<WorkoutService>();
      await workoutService.saveCustomWorkout(workout);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Workout saved!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _deleteWorkout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Workout'),
        content: Text(
          'Delete "${_nameController.text}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final workoutService = context.read<WorkoutService>();
              await workoutService.deleteCustomWorkout(
                widget.editingWorkout!.id,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Workout deleted'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
