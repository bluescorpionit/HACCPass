# ML Kit text recognition: il plugin referenzia anche i riconoscitori
# non-Latin (cinese, devanagari, giapponese, coreano) che questa app NON
# include (serve solo lo script Latin per l'italiano). Il modello Latin
# resta pienamente funzionante.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Prompt 18: la build di release oggi NON è minificata (nessun
# isMinifyEnabled nel build.gradle.kts), quindi R8 non rimuove nulla del
# plugin delle notifiche. Se in futuro si attiva la minificazione,
# decommentare le regole keep raccomandate per flutter_local_notifications
# (la pianificazione serializza con Gson e senza keep può fallire SOLO
# in release):
#-keep class com.dexterous.** { *; }
#-keep class com.google.gson.** { *; }
#-keep class com.google.gson.reflect.TypeToken { *; }
#-keep signatures
