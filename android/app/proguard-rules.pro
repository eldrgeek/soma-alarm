# flutter_local_notifications uses Gson to serialize ScheduledNotification.
# R8 strips the generic type parameter from TypeToken subclasses, causing
# "Missing type parameter" at runtime when scheduling alarms.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type
