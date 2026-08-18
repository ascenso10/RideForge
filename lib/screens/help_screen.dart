import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & FAQ')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader(
            context,
            Icons.bluetooth,
            'Connecting Your Trainer',
          ),
          _buildFaqItem(
            question: 'How do I connect to my smart trainer?',
            answer:
                '1. Make sure Bluetooth is enabled on your phone.\n'
                '2. Turn on your smart trainer.\n'
                '3. On the home screen, tap "Scan for Trainers".\n'
                '4. Your trainer will appear in the list — tap "Connect".\n\n',
          ),
          _buildFaqItem(
            question: 'My trainer is not showing up in the scan.',
            answer:
                '• Make sure the trainer is powered on and not already connected to another device or app (e.g. Zwift).\n'
                '• Grant Bluetooth and Location permissions when prompted — both are required by Android to scan for BLE devices.\n'
                '• Try toggling Bluetooth off and on.\n'
                '• Move your phone closer to the trainer and scan again.',
          ),
          _buildFaqItem(
            question:
                'The app asks for Location permission for Bluetooth — why?',
            answer:
                'Android requires the Location permission to scan for Bluetooth Low Energy (BLE) devices. '
                'The app does not use or store your GPS location.',
          ),

          const SizedBox(height: 8),
          _buildSectionHeader(context, Icons.fitness_center, 'Workouts'),
          _buildFaqItem(
            question: 'How do I start a workout?',
            answer:
                '1. Connect to your trainer first.\n'
                '2. Tap "Do Workout" on the home screen.\n'
                '3. Select a workout from the list and tap "Start".\n\n'
                'The app will automatically control your trainer resistance throughout the session.',
          ),
          _buildFaqItem(
            question: 'How do I create a custom workout?',
            answer:
                '1. Tap "Create Workout" on the home screen.\n'
                '2. Give your workout a name.\n'
                '3. Add intervals by tapping the "+" button — set each interval\'s duration, target power or resistance, and name.\n'
                '4. Tap "Save" when done.\n\n'
                'Your custom workout will then appear in the workout list.',
          ),
          _buildFaqItem(
            question: 'Can I pause or skip intervals during a workout?',
            answer:
                'Yes. During a workout the player shows Pause and Skip buttons.\n\n'
                '• Pause / Resume — stops the timer and holds the current trainer resistance.\n'
                '• Skip forward / backward — jumps to the next or previous interval immediately.',
          ),
          _buildFaqItem(
            question: 'What do the different workout modes mean?',
            answer:
                '• Power (ERG) — the trainer automatically adjusts resistance to hit an exact watt target regardless of your cadence.\n'
                '• Slope — simulates a fixed gradient; your power varies with cadence and gearing.\n'
                '• Resistance — sets a fixed resistance level (0–100 %) on the trainer.',
          ),

          //TODO - Enable when GPX routes are implemented
          /*const SizedBox(height: 8),
          _buildSectionHeader(context, Icons.terrain, 'GPX Routes'),
          _buildFaqItem(
            question: 'How do I follow a GPX route?',
            answer:
                '1. Go to "Manage GPX Routes" and import a .gpx file from your device.\n'
                '2. Tap "Do Workout" → "Follow Track" and select your route.\n'
                '3. The app reads the elevation profile and adjusts the trainer gradient in real time as you ride.',
          ),
          */
          const SizedBox(height: 8),
          _buildSectionHeader(context, Icons.favorite, 'Heart Rate Monitor'),
          _buildFaqItem(
            question: 'How do I use HR measure from my Garmin watch',
            answer:
                '1. Navigate to Heart Rate screen in your watch\n'
                '2. Enable Broadcast HR\n'
                '3. On the app, tap "HR Monitor" on the home screen.\n'
                '4. Tap "Scan for HR Devices" — the app searches for BLE heart rate devices.\n'
                '5. Tap "Connect" next to your device.',
          ),

          /*_buildFaqItem(
            question: 'Which heart rate monitors are supported?',
            answer:
                'Any Bluetooth heart rate monitor that uses the standard '
                'Heart Rate Service is supported. This includes devices from '
                'Polar, Wahoo (TICKR), Garmin, CooSpo, and many others.',
          ),
          _buildFaqItem(
            question: 'My HR monitor connected but shows 0 BPM.',
            answer:
                '• Make sure the strap is wet and making good skin contact.\n'
                '• Try disconnecting and reconnecting.\n'
                '• Some monitors take 10–15 seconds to start broadcasting data after connecting.',
          ),*/
          const SizedBox(height: 8),
          _buildSectionHeader(
            context,
            Icons.history,
            'Workout History & FIT Files',
          ),
          _buildFaqItem(
            question: 'Where are my completed workouts saved?',
            answer:
                'After each workout a FIT file is automatically saved to your device storage. '
                'Tap "Workout History" on the home screen to view all past sessions.',
          ),
          const SizedBox(height: 8),
          _buildSectionHeader(context, Icons.web, 'Official App Page'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('https://ascenso.pt/rideforge');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Visit ascenso.pt/rideforge'),
            ),
          ),

          /*_buildFaqItem(
            question: 'How do I upload a workout to Strava or Garmin Connect?',
            answer:
                '1. Open "Workout History" and tap the workout you want to upload.\n'
                '2. Use the Share button to send the .fit file to Strava, Garmin Connect, '
                'or any other app that accepts FIT files.',
          ),
          _buildFaqItem(
            question: 'Can I export the FIT file manually?',
            answer:
                'Yes. In "Workout History" tap a session and use the Share / Export option '
                'to save or send the .fit file anywhere on your device.',
          ),*/

          /*const SizedBox(height: 8),
          _buildSectionHeader(context, Icons.settings, 'Trainer Settings'),
          _buildFaqItem(
            question: 'What is the Trainer Capability Profile?',
            answer:
                'Different trainers have different maximum gradient and power limits. '
                'Setting the correct profile ensures the app sends values your trainer can actually achieve, '
                'preventing the trainer from ignoring out-of-range commands.',
          ),
          _buildFaqItem(
            question: 'The trainer does not respond to power / resistance commands.',
            answer:
                '• Confirm the trainer is connected (green status on the home screen).\n'
                '• Check that the trainer supports the selected workout mode (ERG, Slope, or Resistance) — not all trainers support all modes.\n'
                '• Try "Manual Control" to test basic commands directly.',
          ),*/
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    IconData icon,
    String title,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem({required String question, required String answer}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 4.0,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
        title: Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
