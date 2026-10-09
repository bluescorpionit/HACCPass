@echo off
REM Build di release Android (appbundle) - nessun segreto nel repository
REM (Prompt 13). Richiede come variabili d'ambiente:
REM   BH_ANCHOR_SECRET          segreto del MAC dell'ancora della prova
REM                             (protezione LEGGERA: sta nel binario e NON
REM                             protegge nessuna licenza, che dipende solo
REM                             dallo store). Accettato anche il vecchio
REM                             nome BH_LICENSE_SECRET come alias.
REM   GOOGLE_SERVER_CLIENT_ID   OAuth Web client ID (obbligatorio su Android)
REM Serve inoltre la firma di release in android\key.properties (vedi
REM docs\identificativi.md): senza di essa gradle fallisce con messaggio
REM chiaro, MAI con un ripiego sulla chiave di debug.

setlocal

set "ANCHOR_SECRET=%BH_ANCHOR_SECRET%"
set "SECRET_NAME=BH_ANCHOR_SECRET"
if "%ANCHOR_SECRET%"=="" (
    if not "%BH_LICENSE_SECRET%"=="" (
        set "ANCHOR_SECRET=%BH_LICENSE_SECRET%"
        set "SECRET_NAME=BH_LICENSE_SECRET (alias storico: rinominare in BH_ANCHOR_SECRET)"
    )
)

if "%ANCHOR_SECRET%"=="" (
    echo ERRORE: manca la variabile d'ambiente BH_ANCHOR_SECRET.
    echo Impostala prima di compilare, ad esempio:
    echo     set BH_ANCHOR_SECRET=^<valore^>
    echo Viene accettato anche il vecchio BH_LICENSE_SECRET come alias.
    echo Il valore serve solo per il MAC dell'ancora della prova.
    exit /b 1
)

echo Uso il segreto da: %SECRET_NAME%

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
    --dart-define=BH_ANCHOR_SECRET="%ANCHOR_SECRET%" ^
    --dart-define=GOOGLE_SERVER_CLIENT_ID="%GOOGLE_SERVER_CLIENT_ID%"

endlocal
