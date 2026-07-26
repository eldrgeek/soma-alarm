# flutter_local_notifications uses Gson to serialize ScheduledNotification.
# R8 strips the generic type parameter from TypeToken subclasses, causing
# "Missing type parameter" at runtime when scheduling alarms.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# Pre-existing (unrelated to on-device AI) — the Meta Wearables DAT
# mock-device SDK's optional media-streaming and companion-device-app
# code paths reference proto classes not bundled in mwdat-mockdevice 0.8.0,
# which made `flutter build apk --release` fail at the R8 minify step even
# with zero changes from this branch (reproduced against
# night/pulse-improvements @ f55e4a4). Pulse doesn't use glasses camera/video
# streaming or companion-device app management, so it's safe to silence these
# rather than keep the (missing) classes.
-dontwarn com.facebook.wearable.common.comms.rtc.hera.proto.**
-dontwarn com.meta.media.stream.proto.**
-dontwarn com.meta.wearable.dat.dwa.capability.stream.internal.protos.**
-dontwarn com.oculus.snappmanager.**
