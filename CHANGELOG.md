# Changelog

## 1.0.6

### Connection recovery
Losing the trainer or heart rate strap mid-ride no longer ends the session.

- **Automatic reconnect.** If a sensor drops during a workout, Ride Forge retries silently (three quick attempts), then keeps retrying every 10 seconds until the sensor is back or you stop the workout.
- **Stall detection.** A trainer that stays connected but stops sending data is treated as a dropped link and recovered the same way.
- **Connection-lost banner.** If the quick attempts fail, a banner appears on every screen naming the sensor, showing whether it is still trying, with **Retry now** and **Pause workout** actions.
- **Background alert.** With the app in the background, you get one "Sensor Connection" notification covering whichever sensors are lost. It updates in place and clears once they reconnect or the workout ends.
- **Brief drops are smoothed over.** Power, speed, cadence, and heart rate hold their last values for up to 10 seconds, and are zeroed only if the link is still down after that.
- **Fewer trainer writes.** Power targets are sent only when they change, with a refresh every 15 seconds, which cuts Bluetooth traffic during steady intervals.

### Intensity control
- A new **Intensity** control in the workout player (normal and immersive views) scales every power target in the running workout from 50% to 150% in 5% steps. Use it to ease off a planned session on a tired day, or push a little harder.
- The new target goes to the trainer immediately. Ramps and the transitions between intervals scale with it.
- Tap the percentage to reset to 100%. Intensity also resets at the start of each ride.

### Under the hood
- Added unit tests for workout models and trainer capabilities, and a CI workflow that runs them.
- Small `flutter analyze` cleanups.