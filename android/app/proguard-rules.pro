# Gavra Android — R8 / ProGuard

-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.geolocator.**
-dontwarn com.baseflow.permissionhandler.**

-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class androidx.biometric.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }
-keep class com.benjaminabel.vibration.** { *; }
-keep class id.flutter.flutter_background_service.** { *; }
-keep class ** extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

-assumenosideeffects class kotlin.jvm.internal.Intrinsics {
    static void checkParameterIsNotNull(java.lang.Object, java.lang.String);
    static void checkExpressionValueIsNotNull(java.lang.Object, java.lang.String);
}

-dontwarn com.google.crypto.tink.**
-keep class com.google.crypto.tink.** { *; }
-dontwarn org.joda.time.**
-keep class org.joda.time.** { *; }

-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*,!code/simplification/string
-optimizationpasses 5
-allowaccessmodification