# Flutter plugins carry their own ProGuard rules.

# WindowManager references vendor/optional classes that are absent on most
# build/runtime classpaths. Suppress warnings/errors for these optional APIs.
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**
