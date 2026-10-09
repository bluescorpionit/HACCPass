#!/usr/bin/env bash
# Build di release Android (appbundle) - nessun segreto nel repository
# (Prompt 13). Richiede come variabili d'ambiente:
#   BH_ANCHOR_SECRET          segreto del MAC dell'ancora della prova
#                             (protezione LEGGERA: sta nel binario e NON
#                             protegge nessuna licenza, che dipende solo
#                             dallo store). Accettato anche il vecchio
#                             nome BH_LICENSE_SECRET come alias.
#   GOOGLE_SERVER_CLIENT_ID   OAuth Web client ID (obbligatorio su Android)
# Serve inoltre la firma di release in android/key.properties (vedi
# docs/identificativi.md): senza di essa gradle fallisce con messaggio
# chiaro, MAI con un ripiego sulla chiave di debug.
set -euo pipefail

cd "$(dirname "$0")/.."

ANCHOR_SECRET="${BH_ANCHOR_SECRET:-}"
SECRET_NAME="BH_ANCHOR_SECRET"
if [ -z "$ANCHOR_SECRET" ] && [ -n "${BH_LICENSE_SECRET:-}" ]; then
    ANCHOR_SECRET="$BH_LICENSE_SECRET"
    SECRET_NAME="BH_LICENSE_SECRET (alias storico: rinominare in BH_ANCHOR_SECRET)"
fi

if [ -z "$ANCHOR_SECRET" ]; then
    echo "ERRORE: manca la variabile d'ambiente BH_ANCHOR_SECRET."
    echo "Impostala prima di compilare, ad esempio:"
    echo "    export BH_ANCHOR_SECRET=<valore>"
    echo "Viene accettato anche il vecchio BH_LICENSE_SECRET come alias."
    echo "Il valore serve solo per il MAC dell'ancora della prova."
    exit 1
fi

echo "Uso il segreto da: $SECRET_NAME"

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
    --dart-define=BH_ANCHOR_SECRET="$ANCHOR_SECRET" \
    --dart-define=GOOGLE_SERVER_CLIENT_ID="$GOOGLE_SERVER_CLIENT_ID"
