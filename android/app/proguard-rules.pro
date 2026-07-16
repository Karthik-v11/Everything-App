# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# flutter_local_notifications — broadcast receivers declared in manifest
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# drift / sqlite3 — native library loaded via JNI
-keep class org.sqlite.** { *; }
-keep class com.dexterous.** { *; }

# flutter_secure_storage — reflection-based keychain access on older APIs
-keep class com.itnomads.fluttersecurestorage.** { *; }

# local_auth — platform channel bridge
-keep class io.flutter.plugins.localauth.** { *; }

# Play Core — referenced by Flutter engine for deferred components; not bundled
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
