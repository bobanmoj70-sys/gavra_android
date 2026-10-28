# Flutter plugins carry their own ProGuard rules.

# WindowManager references vendor/optional classes that are absent on most
# build/runtime classpaths. Suppress warnings/errors for these optional APIs.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# HMS Push SDK je prisutan samo u Huawei buildu i pristupa mu se refleksijom
# iz MainActivity (Class.forName) — bez keep pravila R8 bi klase obrisao/preimenovao.
-dontwarn com.huawei.**
-keep class com.huawei.** { *; }
