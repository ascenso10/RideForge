import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/trainer_service.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _slopeController = TextEditingController(
    text: '5.0',
  );

  @override
  void dispose() {
    _scrollController.dispose();
    _slopeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Data'),
        actions: [
          Switch(
            value: _autoScroll,
            onChanged: (value) {
              setState(() {
                _autoScroll = value;
              });
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Center(child: Text('Auto')),
          ),
        ],
      ),
      body: Consumer<TrainerService>(
        builder: (context, trainerService, child) {
          if (!trainerService.isConnected) {
            return const Center(
              child: Text('Connect to a trainer to view debug data'),
            );
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_autoScroll && _scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });

          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionInfo(trainerService),
                const SizedBox(height: 16),
                _buildRawDataSection(trainerService),
                const SizedBox(height: 16),
                _buildFlagsSection(trainerService),
                const SizedBox(height: 16),
                _buildParsedDataSection(trainerService),
                const SizedBox(height: 16),
                _buildCalibrationSection(trainerService),
                const SizedBox(height: 16),
                _buildSlopeTestingSection(trainerService),
                const SizedBox(height: 16),
                _buildAllValuesSection(trainerService),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionInfo(TrainerService service) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Status: ${service.status}'),
            Text('Connected: ${service.isConnected ? "Yes" : "No"}'),
            if (service.lastDataTimestamp != null)
              Text(
                'Last Data: ${service.lastDataTimestamp!.toString().substring(11, 19)}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRawDataSection(TrainerService service) {
    final rawData = service.lastRawData;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Raw Data Stream',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (rawData != null)
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copyToClipboard(
                      rawData
                          .map(
                            (b) => '0x${b.toRadixString(16).padLeft(2, '0')}',
                          )
                          .join(' '),
                    ),
                    tooltip: 'Copy raw data',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (rawData != null) ...[
              Text('Length: ${rawData.length} bytes'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hex: ${rawData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dec: ${rawData.join(' ')}',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bin: ${rawData.map((b) => b.toRadixString(2).padLeft(8, '0')).join(' ')}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Text('No data received yet'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFlagsSection(TrainerService service) {
    final flags = service.lastFlags;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FTMS Flags Analysis',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (flags != null) ...[
              Text(
                'Flags: 0x${flags.toRadixString(16).padLeft(4, '0')} (${flags.toRadixString(2).padLeft(16, '0')})',
              ),
              const SizedBox(height: 12),
              ...List.generate(8, (bit) {
                bool isSet = (flags & (1 << bit)) != 0;
                String fieldName = _getFlagName(bit);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        isSet
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: isSet ? Colors.green : Colors.grey,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Bit $bit: $fieldName',
                        style: TextStyle(
                          color: isSet ? Colors.green : Colors.grey,
                          fontWeight: isSet
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ] else ...[
              const Text('No flags data yet'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParsedDataSection(TrainerService service) {
    final parsed = service.lastParsedFields;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parsed Values',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (parsed != null) ...[
              _buildValueRow(
                'Speed',
                '${parsed['speed']?.toStringAsFixed(1) ?? '0'} km/h',
              ),
              _buildValueRow(
                'Power',
                '${parsed['power']?.toStringAsFixed(0) ?? '0'} W',
              ),
              _buildValueRow(
                'Cadence',
                '${parsed['cadence']?.toStringAsFixed(0) ?? '0'} rpm',
              ),
              _buildValueRow('Heart Rate', '${parsed['heartRate'] ?? 0} bpm'),
              const Divider(),
              _buildValueRow(
                'Power (before calibration)',
                '${parsed['powerBeforeCalibration']?.toStringAsFixed(0) ?? '0'} W',
                Colors.orange,
              ),
            ] else ...[
              const Text('No parsed data yet'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCalibrationSection(TrainerService service) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Power Calibration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _buildValueRow(
              'Multiplier',
              service.powerMultiplier.toStringAsFixed(3),
            ),
            _buildValueRow(
              'Offset',
              '${service.powerOffset.toStringAsFixed(0)} W',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => _showCalibrationDialog(service),
                  child: const Text('Calibrate'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => service.resetPowerCalibration(),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlopeTestingSection(TrainerService service) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Slope Command Testing',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Test different slope encoding methods to find the correct format for your trainer.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _slopeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Test Slope (%)',
                      hintText: 'Enter slope percentage (e.g., 5.0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => _showSlopeTestDialog(service),
                  child: const Text('Start Tests'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSlopeTestButton(service, 1, 'Standard FTMS', Colors.blue),
                _buildSlopeTestButton(
                  service,
                  2,
                  'As Resistance',
                  Colors.green,
                ),
                _buildSlopeTestButton(
                  service,
                  3,
                  '0.1% Scaling',
                  Colors.orange,
                ),
                _buildSlopeTestButton(service, 4, 'Big Endian', Colors.purple),
                _buildSlopeTestButton(service, 5, 'Power Opcode', Colors.red),
                _buildSlopeTestButton(service, 6, 'Single Byte', Colors.teal),
                _buildSlopeTestButton(service, 7, 'Custom 0x12', Colors.brown),
                _buildSlopeTestButton(
                  service,
                  8,
                  'Wind Position',
                  Colors.indigo,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.yellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Watch your trainer\'s resistance/slope response while testing. The correct method will actually change the trainer\'s difficulty.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlopeTestButton(
    TrainerService service,
    int methodNumber,
    String methodName,
    Color color,
  ) {
    return SizedBox(
      width: 120,
      child: ElevatedButton(
        onPressed: service.isConnected
            ? () => _testSlopeMethod(service, methodNumber)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          side: BorderSide(color: color),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Method $methodNumber',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            Text(
              methodName,
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllValuesSection(TrainerService service) {
    final rawData = service.lastRawData;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data Field Analysis',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (rawData != null && rawData.length >= 4) ...[
              for (int i = 0; i < rawData.length - 1; i++) ...[
                () {
                  int value = rawData[i] | (rawData[i + 1] << 8);
                  bool isReasonablePower = value >= 0 && value <= 500;
                  bool isActualPowerBytes =
                      i == 4; // Bytes 4-5 are the actual power
                  bool isPossibleSpeed = i == 6 && value > 0 && value < 10000;
                  bool isPossibleCadence = i == 8 && value > 0 && value < 600;

                  String fieldType = '';
                  Color? highlightColor;
                  Color? borderColor;

                  if (isActualPowerBytes) {
                    fieldType = 'POWER';
                    highlightColor = Colors.blue.withValues(alpha: 0.2);
                    borderColor = Colors.blue;
                  } else if (isPossibleSpeed) {
                    fieldType = 'SPEED';
                    highlightColor = Colors.green.withValues(alpha: 0.2);
                    borderColor = Colors.green;
                  } else if (isPossibleCadence) {
                    fieldType = 'CADENCE';
                    highlightColor = Colors.orange.withValues(alpha: 0.2);
                    borderColor = Colors.orange;
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: highlightColor,
                      borderRadius: BorderRadius.circular(4),
                      border: borderColor != null
                          ? Border.all(color: borderColor, width: 2)
                          : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            'Bytes $i-${i + 1}:',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Text(
                            '0x${rawData[i].toRadixString(16).padLeft(2, '0')} 0x${rawData[i + 1].toRadixString(16).padLeft(2, '0')}',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            '= $value',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: isReasonablePower
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isReasonablePower ? Colors.green : null,
                            ),
                          ),
                        ),
                        if (fieldType.isNotEmpty)
                          Text(
                            '← $fieldType',
                            style: TextStyle(
                              color: borderColor ?? Colors.grey,
                              fontSize: 12,
                              fontWeight: isActualPowerBytes
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  );
                }(),
              ],
            ] else ...[
              const Text('Waiting for data...'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildValueRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text('$label:')),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  String _getFlagName(int bit) {
    switch (bit) {
      case 0:
        return 'Instantaneous Speed';
      case 1:
        return 'Average Speed';
      case 2:
        return 'Instantaneous Cadence';
      case 3:
        return 'Average Cadence';
      case 4:
        return 'Total Distance';
      case 5:
        return 'Resistance Level';
      case 6:
        return 'Instantaneous Power';
      case 7:
        return 'Average Power';
      default:
        return 'Reserved';
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _showCalibrationDialog(TrainerService service) {
    final multiplierController = TextEditingController(
      text: service.powerMultiplier.toString(),
    );
    final offsetController = TextEditingController(
      text: service.powerOffset.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Power Calibration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: multiplierController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Multiplier',
                hintText: '1.0 = no change, 0.5 = half power',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: offsetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Offset (W)',
                hintText: '0 = no offset, 50 = add 50W',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final multiplier = double.tryParse(multiplierController.text);
              final offset = double.tryParse(offsetController.text);
              if (multiplier != null && offset != null) {
                service.calibratePower(multiplier: multiplier, offset: offset);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _testSlopeMethod(TrainerService service, int methodNumber) async {
    final slopeInput = _getSlopeInputValue();
    if (slopeInput == null) return;

    bool success = false;
    String methodName = '';

    switch (methodNumber) {
      case 1:
        methodName = 'Standard FTMS';
        success = await service.testSlopeMethod1(slopeInput);
        break;
      case 2:
        methodName = 'As Resistance';
        success = await service.testSlopeMethod2(slopeInput);
        break;
      case 3:
        methodName = '0.1% Scaling';
        success = await service.testSlopeMethod3(slopeInput);
        break;
      case 4:
        methodName = 'Big Endian';
        success = await service.testSlopeMethod4(slopeInput);
        break;
      case 5:
        methodName = 'Power Opcode';
        success = await service.testSlopeMethod5(slopeInput);
        break;
      case 6:
        methodName = 'Single Byte';
        success = await service.testSlopeMethod6(slopeInput);
        break;
      case 7:
        methodName = 'Custom 0x12';
        success = await service.testSlopeMethod7(slopeInput);
        break;
      case 8:
        methodName = 'Wind Position';
        success = await service.testSlopeMethod8(slopeInput);
        break;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Method $methodNumber ($methodName): ${success ? 'Sent' : 'Failed'}',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSlopeTestDialog(TrainerService service) {
    final slopeController = TextEditingController(text: '5.0');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Automated Slope Testing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This will test all 8 slope methods automatically with a 3-second delay between each test.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: slopeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Test Slope (%)',
                hintText: 'Enter slope percentage',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Watch your trainer carefully and note which method actually changes the resistance/slope feeling.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final slope = double.tryParse(slopeController.text);
              if (slope != null) {
                Navigator.of(context).pop();
                _runAutomatedSlopeTests(service, slope);
              }
            },
            child: const Text('Start Tests'),
          ),
        ],
      ),
    );
  }

  void _runAutomatedSlopeTests(TrainerService service, double slope) async {
    for (int method = 1; method <= 8; method++) {
      if (!mounted) return;

      // Show which method is being tested
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Testing Method $method... Watch your trainer!'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.blue,
        ),
      );

      // Send the command
      _testSlopeMethod(service, method);

      // Wait 3 seconds before next test
      if (method < 8) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All slope tests completed! Which method worked?'),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  double? _getSlopeInputValue() {
    return double.tryParse(_slopeController.text) ?? 5.0;
  }
}
