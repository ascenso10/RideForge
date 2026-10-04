/// Health of the BLE link to a sensor (trainer or heart rate monitor).
///
/// [reconnecting] is the silent first phase after an unexpected drop during a
/// workout; [lost] means those attempts failed and the user should be told
/// (retries keep running in the background).
enum DeviceLinkState { disconnected, connected, reconnecting, lost }
