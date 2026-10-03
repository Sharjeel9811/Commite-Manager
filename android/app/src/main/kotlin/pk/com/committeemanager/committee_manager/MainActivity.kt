package pk.com.committeemanager.committee_manager

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * `FlutterFragmentActivity` rather than `FlutterActivity`.
 *
 * The biometric prompt is a fragment, so `local_auth` cannot attach it to a
 * plain `FlutterActivity`. This is the single most common cause of
 * "biometrics never appear" on Android.
 */
class MainActivity : FlutterFragmentActivity()
