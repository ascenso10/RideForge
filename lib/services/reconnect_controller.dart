import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/device_link_state.dart';

/// Reconnect policy shared by the trainer and heart rate services.
///
/// After a drop it makes a short burst of silent attempts
/// ([DeviceLinkState.reconnecting]). If they all fail it reports
/// [DeviceLinkState.lost] and keeps retrying in the background until it
/// succeeds or is cancelled.
class ReconnectController {
  ReconnectController({
    required this.label,
    required this.attempt,
    required this.onChanged,
  });

  /// Device name for logs.
  final String label;

  /// Makes one reconnect attempt and returns whether the link is back.
  /// [isCancelled] turns true if [cancel] was called meanwhile; the attempt
  /// should then avoid committing the new link.
  final Future<bool> Function(bool Function() isCancelled) attempt;

  /// Called whenever [phase] or [attemptInFlight] changes.
  final VoidCallback onChanged;

  static const List<Duration> _burstBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];
  static const Duration _backgroundRetryInterval = Duration(seconds: 10);

  /// Timeout each attempt should use for its BLE connect, so trainer and HR
  /// bursts finish together and the lost banner appears once.
  static const Duration attemptTimeout = Duration(seconds: 6);

  DeviceLinkState? _phase;
  bool _attemptInFlight = false;
  // Bumped on cancel so in-flight work from an older run is abandoned.
  int _generation = 0;
  Timer? _retryTimer;

  /// [DeviceLinkState.reconnecting], [DeviceLinkState.lost], or null when idle.
  DeviceLinkState? get phase => _phase;
  bool get isActive => _phase != null;
  bool get attemptInFlight => _attemptInFlight;

  /// Starts the reconnect sequence. [prepare] runs before the first attempt.
  Future<void> start({Future<void> Function()? prepare}) async {
    cancel();
    final generation = _generation;
    _phase = DeviceLinkState.reconnecting;
    onChanged();

    if (prepare != null) await prepare();

    for (final delay in _burstBackoff) {
      await Future.delayed(delay);
      if (generation != _generation) return;
      if (await _attempt(generation)) return;
    }

    if (generation != _generation) return;
    debugPrint('$label reconnect failed - reporting connection lost');
    _phase = DeviceLinkState.lost;
    onChanged();
    _scheduleRetry(generation);
  }

  /// Immediate attempt, for the "Retry now" action while [DeviceLinkState.lost].
  Future<void> retryNow() async {
    if (_phase != DeviceLinkState.lost || _attemptInFlight) return;

    _retryTimer?.cancel();
    final generation = _generation;
    if (await _attempt(generation)) return;
    if (generation == _generation) _scheduleRetry(generation);
  }

  /// Abandons any reconnect in progress. Does not notify; the owner does.
  void cancel() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _phase = null;
  }

  void _scheduleRetry(int generation) {
    _retryTimer?.cancel();
    _retryTimer = Timer(_backgroundRetryInterval, () async {
      if (generation != _generation) return;
      if (!_attemptInFlight && await _attempt(generation)) return;
      if (generation == _generation) _scheduleRetry(generation);
    });
  }

  Future<bool> _attempt(int generation) async {
    _attemptInFlight = true;
    onChanged();

    try {
      debugPrint('$label reconnect attempt...');
      final reconnected = await attempt(() => generation != _generation);
      if (reconnected && generation == _generation) {
        debugPrint('$label reconnected');
        _retryTimer?.cancel();
        _phase = null;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('$label reconnect attempt failed: $e');
      return false;
    } finally {
      _attemptInFlight = false;
      onChanged();
    }
  }
}
