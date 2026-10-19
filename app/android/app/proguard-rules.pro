# Kelimeta - Minimal ProGuard / R8 Kuralları
# Gereksiz geniş kurallardan kaçınılmış, yalnızca runtime refleksiyonu kullanan
# Flutter platform kanalları, Firebase Auth ve Google Sign-In bileşenleri hedeflenmiştir.

# Flutter Platform & Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase Auth & Google Play Services
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.common.api.** { *; }

