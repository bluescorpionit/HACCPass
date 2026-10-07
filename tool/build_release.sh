#!/usr/bin/env bash
# Build di release Android (appbundle) - nessun segreto nel repository
# (Prompt 10, E). Richiede come variabili d'ambiente:
#   BH_LICENSE_SECRET        segreto HMAC delle chiavi di licenza
#   GOOGLE_SERVER_CLIENT_ID  OAuth Web client ID (obbligatorio su Android)
# Più la firma di release in android/key.properties (vedi
# docs/identificativi.md): senza di essa gradle fallisce con messaggio
# chiaro, MAI con un ripiego sulla chiave di debug.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "${BH_LICENSE_SECRET:-}" ]; then
    echo "ERRORE: manca la variabile d'ambiente BH_LICENSE_SECRET."
    echo "Impostala prima di compilare, ad esempio:"
    echo "    export BH_LICENSE_SECRET=<valore>"
    echo "Il valore va conservato insieme alla keystore (docs/identificativi.md)."
    exit 1
fi

if [ -z "${GOOGLE_SERVER_CLIENT_ID:-}" ]; then
    echo "ERRORE: manca la variabile d'ambiente GOOGLE_SERVER_CLIENT_ID."
    echo "Impostala prima di compilare, ad esempio:"
    echo "    export GOOGLE_SERVER_CLIENT_ID=<web-oauth-client-id>"
    echo "Su Android il collegamento Google Drive non funziona senza."
    exit 1
fi

if [ ! -f android/key.properties ]; then
    echo "ERRORE: manca android/key.properties (firma di release)."
    echo "Crea la keystore di upload e compila i dati come da"
    echo "docs/identificativi.md."
    exit 1
fi

flutter build appbundle --release \
    --dart-define=BH_LICENSE_SECRET="$BH_LICENSE_SECRET" \
    --dart-define=GOOGLE_SERVER_CLIENT_ID="$GOOGLE_SERVER_CLIENT_ID"
