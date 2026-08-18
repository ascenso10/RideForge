import 'package:flutter/material.dart';
import '../services/garmin_service.dart';

/// Widget for uploading workout FIT files to Garmin Connect
class GarminUploadWidget extends StatefulWidget {
  final String fitFilePath;
  final VoidCallback? onUploadComplete;
  final VoidCallback? onUploadFailed;

  const GarminUploadWidget({
    super.key,
    required this.fitFilePath,
    this.onUploadComplete,
    this.onUploadFailed,
  });

  @override
  State<GarminUploadWidget> createState() => _GarminUploadWidgetState();
}

class _GarminUploadWidgetState extends State<GarminUploadWidget> {
  final GarminService _garminService = GarminService();
  bool _isUploading = false;
  bool _uploadSuccess = false;
  bool _uploadFailed = false;
  String? _errorMessage;

  Future<void> _uploadToGarmin() async {
    setState(() {
      _isUploading = true;
      _uploadSuccess = false;
      _uploadFailed = false;
      _errorMessage = null;
    });

    try {
      // Check if connected
      final isConnected = await _garminService.isConnected();
      if (!isConnected) {
        throw Exception(
          'Not connected to Garmin. Please configure Garmin in settings.',
        );
      }

      // Upload the FIT file
      final success = await _garminService.uploadActivity(widget.fitFilePath);

      setState(() {
        _isUploading = false;
        _uploadSuccess = success;
        _uploadFailed = !success;
      });

      if (success) {
        widget.onUploadComplete?.call();
      } else {
        widget.onUploadFailed?.call();
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _uploadFailed = true;
        _errorMessage = e.toString();
      });
      widget.onUploadFailed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _uploadSuccess
                      ? Icons.check_circle
                      : _uploadFailed
                      ? Icons.error
                      : Icons.cloud_upload,
                  color: _uploadSuccess
                      ? Colors.green
                      : _uploadFailed
                      ? Colors.red
                      : Colors.blue,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload to Garmin Connect',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _uploadSuccess
                            ? 'Successfully uploaded to Garmin!'
                            : _uploadFailed
                            ? 'Upload failed'
                            : 'Share your workout with Garmin',
                        style: TextStyle(
                          fontSize: 13,
                          color: _uploadSuccess
                              ? Colors.green[700]
                              : _uploadFailed
                              ? Colors.red[700]
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading || _uploadSuccess
                    ? null
                    : _uploadToGarmin,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_uploadSuccess ? Icons.check : Icons.cloud_upload),
                label: Text(
                  _isUploading
                      ? 'Uploading...'
                      : _uploadSuccess
                      ? 'Uploaded'
                      : _uploadFailed
                      ? 'Retry Upload'
                      : 'Upload to Garmin',
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: _uploadSuccess
                      ? Colors.green
                      : _uploadFailed
                      ? Colors.orange
                      : Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (!_uploadSuccess && !_isUploading) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Make sure you\'re connected to Garmin in Settings',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Function to upload a FIT file to Garmin Connect
/// Can be used standalone without the widget
Future<bool> uploadToGarmin(String fitFilePath) async {
  final garminService = GarminService();

  try {
    // Check if connected
    final isConnected = await garminService.isConnected();
    if (!isConnected) {
      throw Exception('Not connected to Garmin');
    }

    // Upload the file
    return await garminService.uploadActivity(fitFilePath);
  } catch (e) {
    debugPrint('Error uploading to Garmin: $e');
    return false;
  }
}
