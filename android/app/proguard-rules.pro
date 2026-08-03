# Gavra Android — R8 / ProGuard (release)

-keepattributes *Annotation*,SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class ** extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Plugins actually used (see pubspec.yaml)
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class id.flutter.flutter_background_service.** { *; }

-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

-dontwarn com.google.crypto.tink.**
-dontwarn org.joda.time.**