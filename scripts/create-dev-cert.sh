#!/bin/bash
set -euo pipefail

# create-dev-cert.sh — Stabile lokale Code-Signing-Identitaet fuer rede
#
# Problem: build.sh signiert standardmaessig ad-hoc (`codesign --sign -`). Jeder
# Rebuild erzeugt einen neuen CDHash. macOS-TCC hat die Bedienungshilfen-/Mikrofon-/
# Eingabeueberwachungs-Freigabe gegen den ALTEN Code-Requirement gespeichert ->
# `AXIsProcessTrusted()` liefert nach dem Rebuild `false`, obwohl der Toggle in den
# Systemeinstellungen noch "an" aussieht.
#
# Loesung: ein einmal erzeugtes, selbst-signiertes Code-Signing-Zertifikat
# "rede Local Dev" gibt jedem Build einen STABILEN Code-Requirement. Damit
# ueberleben die Freigaben kuenftige Rebuilds.
#
# Dieses Skript ist idempotent: existiert die Identitaet bereits, passiert nichts.
# Es ist sicher, mehrfach auszufuehren. Beim ersten Lauf fragt macOS einmalig nach
# dem Keychain-Passwort (Import + Zugriffsrecht fuer codesign) — das ist gewollt.
#
# KEIN bezahlter Apple-Developer-Account noetig.

IDENTITY_NAME="rede Local Dev"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if [ ! -f "$LOGIN_KEYCHAIN" ]; then
    # Aelterer Pfad ohne -db-Suffix als Fallback.
    LOGIN_KEYCHAIN="$(security default-keychain 2>/dev/null | tr -d ' "' || echo "login.keychain")"
fi
SYSTEM_KEYCHAIN="/Library/Keychains/System.keychain"

print_header() {
    echo ""
    echo "=== rede: Lokale Code-Signing-Identitaet einrichten ==="
    echo ""
}

add_unique_keychain_path() {
    local candidate="$1"

    if [ ! -f "$candidate" ]; then
        return
    fi

    if printf '%s\n' "$KEYCHAIN_SEARCH_LIST" | grep -Fxq "$candidate"; then
        return
    fi

    KEYCHAIN_SEARCH_LIST="${KEYCHAIN_SEARCH_LIST}${candidate}
"
}

ensure_keychain_search_list() {
    local raw_entry
    local normalized_entry
    local part

    KEYCHAIN_SEARCH_LIST=""
    add_unique_keychain_path "$LOGIN_KEYCHAIN"

    while IFS= read -r raw_entry; do
        normalized_entry="$(printf '%s' "$raw_entry" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"

        if [ -f "$normalized_entry" ]; then
            add_unique_keychain_path "$normalized_entry"
            continue
        fi

        # Repair a malformed search list entry such as
        # "login.keychain-db /Library/Keychains/System.keychain".
        for part in $normalized_entry; do
            add_unique_keychain_path "$part"
        done
    done < <(security list-keychains -d user 2>/dev/null || true)

    add_unique_keychain_path "$SYSTEM_KEYCHAIN"

    printf '%s' "$KEYCHAIN_SEARCH_LIST" | xargs security list-keychains -d user -s
}

identity_can_sign() {
    local test_dir
    test_dir="$(mktemp -d -t rede-codesign-test)"
    local test_file="$test_dir/codesign-test"
    printf 'rede' > "$test_file"

    if codesign --force --sign "$IDENTITY_NAME" "$test_file" >/dev/null 2>&1; then
        rm -rf "$test_dir"
        return 0
    fi

    rm -rf "$test_dir"
    return 1
}

trust_certificate_file() {
    local certificate_file="$1"

    # A self-signed certificate is visible to Keychain after import, but codesign
    # will still reject it until it is trusted for the Code Signing policy.
    security add-trusted-cert \
        -r trustRoot \
        -p codeSign \
        -k "$LOGIN_KEYCHAIN" \
        "$certificate_file"
}

finish_success() {
    echo ""
    echo "Erfolg! Die Identitaet \"$IDENTITY_NAME\" ist eingerichtet und einsatzbereit."
    echo ""
    echo "Naechste Schritte:"
    echo "  1. Baue rede neu mit:   ./build.sh"
    echo "     (build.sh erkennt die Identitaet automatisch und signiert damit stabil)"
    echo "  2. EINMALIG: oeffne Systemeinstellungen > Datenschutz & Sicherheit >"
    echo "     Bedienungshilfen. Entferne dort einen evtl. vorhandenen alten"
    echo "     \"rede\"-Eintrag mit dem Minus (-) und fuege rede neu hinzu"
    echo "     bzw. aktiviere den Schalter erneut. Dasselbe ggf. fuer Mikrofon und"
    echo "     Eingabeueberwachung."
    echo "  3. Ab jetzt ueberleben diese Freigaben kuenftige Rebuilds."
    echo ""
    exit 0
}

print_header
ensure_keychain_search_list

if identity_can_sign; then
    echo "Die Identitaet \"$IDENTITY_NAME\" ist bereits vorhanden und kann signieren."
    echo "Es ist nichts zu tun. Baue rede einfach mit ./build.sh und die"
    echo "Bedienungshilfen-Freigabe ueberlebt kuenftige Rebuilds."
    echo ""
    exit 0
fi

if security find-certificate -c "$IDENTITY_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    echo "Die Identitaet \"$IDENTITY_NAME\" ist vorhanden, aber noch nicht fuer Code Signing vertrauenswuerdig."
    echo "Setze jetzt den Trust fuer Code Signing. macOS kann dafuer dein Keychain-Passwort abfragen."
    echo ""

    REPAIR_DIR="$(mktemp -d -t rede-dev-cert-repair)"
    trap 'rm -rf "$REPAIR_DIR"' EXIT
    EXISTING_CERT_FILE="$REPAIR_DIR/existing-cert.pem"
    security find-certificate -c "$IDENTITY_NAME" -p "$LOGIN_KEYCHAIN" > "$EXISTING_CERT_FILE"
    trust_certificate_file "$EXISTING_CERT_FILE"

    echo ""
    echo "Verifiziere die reparierte Identitaet ..."
    if identity_can_sign; then
        finish_success
    fi

    echo ""
    echo "Warnung: Die Trust-Reparatur ist fehlgeschlagen."
    echo "Pruefe in der Schluesselbundverwaltung, ob \"$IDENTITY_NAME\" im Anmeldung-Keychain"
    echo "liegt und fuer Code Signing auf \"Immer vertrauen\" gesetzt ist."
    echo ""
    exit 1
fi

echo "Erzeuge eine neue selbst-signierte Code-Signing-Identitaet \"$IDENTITY_NAME\"."
echo "macOS fragt gleich einmalig nach deinem Keychain-Passwort — das ist normal."
echo ""

# Temporaeres Arbeitsverzeichnis, das in jedem Fall aufgeraeumt wird.
WORK_DIR="$(mktemp -d -t rede-dev-cert)"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

KEY_FILE="$WORK_DIR/key.pem"
CERT_FILE="$WORK_DIR/cert.pem"
P12_FILE="$WORK_DIR/identity.p12"
CONFIG_FILE="$WORK_DIR/openssl.cnf"
# Zufaelliges Wegwerf-Passwort fuer den pkcs12-Container (nur fuer den Import).
P12_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24 || true)"
if [ -z "$P12_PASSWORD" ]; then
    P12_PASSWORD="rede-dev-$$"
fi

# OpenSSL-Konfiguration: WICHTIG ist extendedKeyUsage = critical, codeSigning.
# Genau das macht das Zertifikat fuer `codesign` verwendbar.
cat > "$CONFIG_FILE" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3_codesign
prompt = no

[ dn ]
CN = $IDENTITY_NAME

[ v3_codesign ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

echo "1/3  Schluessel + Zertifikat erzeugen ..."
openssl req \
    -x509 \
    -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days 3650 \
    -nodes \
    -config "$CONFIG_FILE" \
    >/dev/null 2>&1

echo "2/3  In einen PKCS#12-Container verpacken ..."
# -legacy ist auf neueren OpenSSL-Versionen noetig, damit der macOS-Keychain-Import
# das Format akzeptiert.
openssl pkcs12 \
    -export \
    -legacy \
    -inkey "$KEY_FILE" \
    -in "$CERT_FILE" \
    -name "$IDENTITY_NAME" \
    -out "$P12_FILE" \
    -passout "pass:$P12_PASSWORD" \
    >/dev/null 2>&1

echo "3/3  In den Login-Keychain importieren (Passwort-Abfrage moeglich) ..."
# -T /usr/bin/codesign erlaubt codesign den Zugriff auf den privaten Schluessel,
# ohne dass bei jedem Build erneut nachgefragt wird.
security import "$P12_FILE" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

echo ""
echo "Setze Trust fuer Code Signing ..."
trust_certificate_file "$CERT_FILE"

# Verifikation per Wegwerf-Test-Signatur (zuverlaessiger als nur find-identity):
# wir signieren eine kleine Testdatei und pruefen, ob es klappt.
echo ""
echo "Verifiziere die neue Identitaet ..."
if identity_can_sign; then
    finish_success
else
    echo ""
    echo "Warnung: Die Test-Signatur ist fehlgeschlagen."
    echo "Der Import lief durch, aber codesign kann die Identitaet noch nicht nutzen."
    echo "Versuche es nach einem Ab- und Anmelden erneut, oder pruefe in der"
    echo "Schluesselbundverwaltung, ob \"$IDENTITY_NAME\" im Anmeldung-Keychain liegt."
    echo ""
    exit 1
fi
