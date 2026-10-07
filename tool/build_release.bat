@echo off
REM Build di release Android (appbundle) - nessun segreto nel repository
REM (Prompt 10, E). Richiede come variabili d'ambiente:
REM   BH_LICENSE_SECRET        segreto HMAC delle chiavi di licenza
REM   GOOGLE_SERVER_CLIENT_ID  OAuth Web client ID (obbligatorio su Android)
REM Serve inoltre la firma di release in android\key.properties (vedi
REM docs\identificativi.md): senza di essa gradle fallisce con messaggio
REM chiaro, MAI con un ripiego sulla chiave di debug.

setlocal

if "%BH_LICENSE_SECRET%"=="" (
    echo ERRORE: manca la variabile d'ambiente BH_LICENSE_SECRET.
    echo Impostala prima di compilare, ad esempio:
    echo     set BH_LICENSE_SECRET=^<valore^>
    echo Il valore va conservato insieme alla keystore (docs\identificativi.md).
    exit /b 1
)

if "%GOOGLE_SERVER_CLIENT_ID%"=="" (
    echo ERRORE: manca la variabile d'ambiente GOOGLE_SERVER_CLIENT_ID.
    echo Impostala prima di compilare, ad esempio:
    echo     set GOOGLE_SERVER_CLIENT_ID=^<web-oauth-client-id^>
    echo Su Android il collegamento Google Drive non funziona senza.
    exit /b 1
)

if not exist "%~dp0..\android\key.properties" (
    echo ERRORE: manca android\key.properties (firma di release).
    echo Crea la keystore di upload e compila i dati come da
    echo docs\identificativi.md.
    exit /b 1
)

flutter build appbundle --release ^
    --dart-define=BH_LICENSE_SECRET="%BH_LICENSE_SECRET%" ^
    --dart-define=GOOGLE_SERVER_CLIENT_ID="%GOOGLE_SERVER_CLIENT_ID%"

endlocal
