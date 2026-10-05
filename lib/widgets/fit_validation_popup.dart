import 'package:flutter/material.dart';
import '../models/workout_models.dart';

class FitValidationPopup extends StatelessWidget {
  final FitValidationResult result;

  const FitValidationPopup({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.isValid ? Icons.check_circle : Icons.error,
                  color: result.isValid ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'FIT File Validation',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),

            if (!result.isValid) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Error: ${result.error ?? "Unknown error"}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (result.isValid) ...[
              // File Info Section
              _buildSection('File Information', [
                _buildInfoRow(
                  'File Size',
                  '${(result.fileSize / 1024).toStringAsFixed(1)} KB',
                ),
                _buildInfoRow('Total Messages', result.messageCount.toString()),
                _buildInfoRow('Record Count', result.recordCount.toString()),
              ]),

              // Timestamps Section
              if (result.workoutStartTime != null || result.timeCreated != null)
                _buildSection('Timestamps', [
                  if (result.workoutStartTime != null)
                    _buildInfoRow(
                      'Workout Start Time',
                      _formatDateTime(result.workoutStartTime!),
                      subtitle: 'Original workout start time',
                    ),
                  if (result.timeCreated != null)
                    _buildInfoRow(
                      'FIT File Created',
                      _formatDateTime(result.timeCreated!),
                      subtitle: 'When FIT file was generated',
                    ),
                ]),

              // Timing Section (Most Important)
              if (result.sessionTotalElapsedTime != null &&
                  result.sessionTotalTimerTime != null)
                _buildSection('Timing Information', [
                  _buildInfoRow(
                    'Total Elapsed Time',
                    result.formatDuration(result.sessionElapsedDuration),
                    subtitle: 'Wall-clock time (includes pauses)',
                  ),
                  _buildInfoRow(
                    'Total Timer Time',
                    result.formatDuration(result.sessionTimerDuration),
                    subtitle: 'Workout time (excludes pauses)',
                  ),
                  if (result.pauseTime != null &&
                      result.pauseTime!.inSeconds > 0)
                    _buildInfoRow(
                      'Pause Time',
                      result.formatDuration(result.pauseTime),
                      highlight: true,
                    ),
                ]),

              // Power & Performance Section
              if (result.sessionAvgPower != null ||
                  result.sessionMaxPower != null)
                _buildSection('Power & Performance', [
                  if (result.sessionAvgPower != null)
                    _buildInfoRow(
                      'Average Power',
                      '${result.sessionAvgPower}W',
                    ),
                  if (result.sessionMaxPower != null)
                    _buildInfoRow('Max Power', '${result.sessionMaxPower}W'),
                  if (result.sessionAvgSpeed != null)
                    _buildInfoRow(
                      'Average Speed',
                      '${(result.sessionAvgSpeed! * 3.6).toStringAsFixed(1)} km/h',
                    ),
                  if (result.sessionTotalDistance != null)
                    _buildInfoRow(
                      'Total Distance',
                      '${(result.sessionTotalDistance! / 1000).toStringAsFixed(2)} km',
                    ),
                ]),

              // Sample Data Section
              if (result.firstRecordInfo != null ||
                  result.lastRecordInfo != null)
                _buildSection('Sample Data Points', [
                  if (result.firstRecordInfo != null)
                    _buildInfoRow('First Record', result.firstRecordInfo!),
                  if (result.lastRecordInfo != null)
                    _buildInfoRow('Last Record', result.lastRecordInfo!),
                ]),
            ],

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    String? subtitle,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: highlight ? const EdgeInsets.all(8) : null,
        decoration: highlight
            ? BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: highlight ? Colors.orange.shade700 : null,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                    color: highlight
                        ? Colors.orange.shade700
                        : Colors.grey[700],
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Format DateTime for display
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }
}

/// Helper function to show the FIT validation popup
void showFitValidationPopup(BuildContext context, FitValidationResult result) {
  showDialog(
    context: context,
    builder: (context) => FitValidationPopup(result: result),
  );
}
