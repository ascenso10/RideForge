import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/strava_service.dart';
import '../screens/strava_settings_screen.dart';

/// Widget for uploading workout FIT files to Strava
class StravaUploadWidget extends StatefulWidget {
  final String fitFilePath;
  final VoidCallback? onUploadComplete;
  final VoidCallback? onUploadFailed;

  const StravaUploadWidget({
    super.key,
    required this.fitFilePath,
    this.onUploadComplete,
    this.onUploadFailed,
  });

  @override
  State<StravaUploadWidget> createState() => _StravaUploadWidgetState();
}

class _StravaUploadWidgetState extends State<StravaUploadWidget> {
  bool _isUploading = false;
  bool _uploadSuccess = false;
  bool _uploadFailed = false;
  bool _notConnected = false;
  String? _errorMessage;

  Future<void> _uploadToStrava() async {
    setState(() {
      _isUploading = true;
      _uploadSuccess = false;
      _uploadFailed = false;
      _notConnected = false;
      _errorMessage = null;
    });

    try {
      // Get a valid (auto-refreshed if needed) access token
      final accessToken = await StravaService.instance.getValidAccessToken();

      if (accessToken == null) {
        setState(() => _notConnected = true);
        throw Exception(
          'Not connected to Strava. Please connect your account first.',
        );
      }

      // Upload the FIT file
      final success = await uploadToStrava(widget.fitFilePath, accessToken);

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
        _errorMessage = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
      });
      widget.onUploadFailed?.call();
    }
  }

  Future<void> _openStravaSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StravaSettingsScreen()));
    if (StravaService.instance.isConnected) {
      _uploadToStrava();
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
                      : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload to Strava',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _uploadSuccess
                            ? 'Successfully uploaded to Strava!'
                            : _uploadFailed
                            ? 'Upload failed'
                            : 'Share your workout with Strava',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_notConnected) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openStravaSettings,
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Connect to Strava'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
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
                    : _uploadToStrava,
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
                      : 'Upload to Strava',
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: _uploadSuccess
                      ? Colors.green
                      : _uploadFailed
                      ? Colors.orange
                      : Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Function to upload a FIT file to Strava
Future<bool> uploadToStrava(String fitFilePath, String accessToken) async {
  try {
    final url = Uri.parse("https://www.strava.com/api/v3/uploads");
    final request = http.MultipartRequest("POST", url)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['data_type'] = 'fit'
      ..files.add(await http.MultipartFile.fromPath('file', fitFilePath));

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode == 201) {
      debugPrint("Strava upload success: $body");
      return true;
    } else {
      debugPrint("Strava upload failed: ${response.statusCode} $body");
      return false;
    }
  } catch (e) {
    debugPrint('Error uploading to Strava: $e');
    return false;
  }
}
