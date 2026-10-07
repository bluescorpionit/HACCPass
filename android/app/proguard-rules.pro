# ML Kit text recognition: il plugin referenzia anche i riconoscitori
# non-Latin (cinese, devanagari, giapponese, coreano) che questa app NON
# include (serve solo lo script Latin per l'italiano). Il modello Latin
# resta pienamente funzionante.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
