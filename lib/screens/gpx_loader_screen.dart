import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/workout_service.dart';

class GpxLoaderScreen extends StatefulWidget {
  const GpxLoaderScreen({super.key});

  @override
  State<GpxLoaderScreen> createState() => _GpxLoaderScreenState();
}

class _GpxLoaderScreenState extends State<GpxLoaderScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String? _selectedFileName;
  List<int>? _selectedFileBytes;
  bool _isLoading = false;
  bool _disableProcessing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Load GPX Track')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Load GPX File',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.folder_open, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'GPX File',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_selectedFileName != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedFileName!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedFileName = null;
                                    _selectedFileBytes = null;
                                  });
                                },
                                icon: const Icon(Icons.close, size: 20),
                                tooltip: 'Remove file',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _pickGpxFile,
                          icon: Icon(
                            _selectedFileName != null
                                ? Icons.swap_horiz
                                : Icons.upload_file,
                          ),
                          label: Text(
                            _selectedFileName != null
                                ? 'Choose Different File'
                                : 'Select GPX File',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Workout Name',
                    hintText: 'e.g., Morning Hill Climb',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Describe your route...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _disableProcessing,
                  onChanged: (value) {
                    setState(() {
                      _disableProcessing = value ?? false;
                    });
                  },
                  title: const Text('Disable GPX Processing'),
                  subtitle: const Text(
                    'Use raw track points without smoothing or elevation filtering',
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading || _selectedFileBytes == null)
                        ? null
                        : _loadGpxFile,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_road),
                    label: Text(
                      _isLoading ? 'Loading...' : 'Add to Workout Library',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedFileBytes != null
                          ? Colors.green
                          : null,
                      foregroundColor: _selectedFileBytes != null
                          ? Colors.white
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickGpxFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
        allowMultiple: false,
      );

      if (result != null) {
        final file = result.files.single;

        // Get file bytes (works on all platforms)
        List<int>? bytes;
        if (file.bytes != null) {
          bytes = file.bytes!;
        } else if (file.path != null) {
          // Fallback for desktop platforms
          final fileContent = await File(file.path!).readAsBytes();
          bytes = fileContent;
        }

        if (bytes != null) {
          setState(() {
            _selectedFileName = file.name;
            _selectedFileBytes = bytes;

            // Auto-populate name if empty
            if (_nameController.text.isEmpty) {
              // Remove .gpx extension and use as default name
              final nameWithoutExtension = file.name.replaceAll('.gpx', '');
              _nameController.text = nameWithoutExtension;
            }
          });
        } else {
          throw Exception('Could not read file content');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadGpxFile() async {
    if (_selectedFileBytes == null ||
        _selectedFileName == null ||
        _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a GPX file and enter a name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final workoutService = context.read<WorkoutService>();
      await workoutService.loadGpxWorkoutFromBytes(
        _selectedFileBytes!,
        _selectedFileName!,
        _nameController.text.trim(),
        _descriptionController.text.trim().isEmpty
            ? 'GPX Track Workout'
            : _descriptionController.text.trim(),
        disableProcessing: _disableProcessing,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPX file loaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form
        setState(() {
          _selectedFileName = null;
          _selectedFileBytes = null;
        });
        _nameController.clear();
        _descriptionController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading GPX file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
