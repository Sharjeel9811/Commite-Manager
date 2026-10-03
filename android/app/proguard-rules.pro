# Flutter's own rules are contributed by the Flutter Gradle plugin.
# The entries below protect the plugin entry points that are only reached
# through reflection, which is how the Android side of sqflite, local_auth and
# flutter_local_notifications find their Java/Kotlin classes.

-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# local_auth
-keep class androidx.biometric.** { *; }

# flutter_local_notifications
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-dontwarn com.dexterous.**

# Play Core (deferred components / split installs)
#
# The Flutter engine contains PlayStoreDeferredComponentManager, which statically
# references com.google.android.play.core.*. This app ships as a single APK and
# never uses deferred components, so those classes are not on the classpath. R8
# treats the references as a hard error unless it is told to ignore them.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
