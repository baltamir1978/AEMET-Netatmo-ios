#!/bin/bash
# Compila, firma y sube Tiempo ES a App Store Connect para TestFlight.
#
#   ./Tools/testflight.sh             # archiva y sube
#   ./Tools/testflight.sh --dry-run   # dice lo que haría, sin compilar ni subir
#
# CREDENCIALES: NUNCA EN EL REPOSITORIO, QUE ES PÚBLICO.
#
# La clave de la API de App Store Connect es de la cuenta, común a todas las apps.
# Se lee de variables de entorno o de ~/.config/appstoreconnect/testflight.env:
#
#   ASC_KEY_ID=ABC123DEFG
#   ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
#   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_ABC123DEFG.p8   # opcional
#
# NÚMERO DE BUILD: la fecha y la hora, AAMMDDHHMM. Siempre crece y no hay contador
# que guardar. Se pasa a todos los targets, así que app y widget coinciden. La
# versión visible (MARKETING_VERSION) se cambia a mano en el proyecto.
set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

say() { printf '==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

CONFIG="$HOME/.config/appstoreconnect/testflight.env"
if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG"
fi

[ -n "${ASC_KEY_ID:-}" ] || fail "Falta ASC_KEY_ID. Ponlo en $CONFIG o en el entorno."
[ -n "${ASC_ISSUER_ID:-}" ] || fail "Falta ASC_ISSUER_ID. Ponlo en $CONFIG o en el entorno."
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
KEY_PATH="${KEY_PATH/#\~/$HOME}"
[ -f "$KEY_PATH" ] || fail "No encuentro la clave .p8 en $KEY_PATH."

# Sin Secrets.swift no compila, y con el .example sale una app sin claves.
[ -f AppPersonal/Secrets.swift ] || fail "Falta AppPersonal/Secrets.swift (copia Secrets.swift.example)."

# xcode-select apunta a las CommandLineTools, que no traen xcodebuild.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUILD_NUMBER="$(date +%y%m%d%H%M)"
VERSION="$(grep -m1 'MARKETING_VERSION' AppPersonal.xcodeproj/project.pbxproj | sed -E 's/.*= *([^;]*);.*/\1/')"
ARCHIVE="build/testflight/TiempoES-$VERSION-$BUILD_NUMBER.xcarchive"
EXPORT_DIR="build/testflight/export-$BUILD_NUMBER"
OPTIONS="$(mktemp -t tiempoes-export).plist"
trap 'rm -f "$OPTIONS"' EXIT

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

# Exportar con destino «upload» sube directamente: sin altool ni Transporter.
cat > "$OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>upload</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST

say "Tiempo ES $VERSION ($BUILD_NUMBER)"
say "Clave de la API: $ASC_KEY_ID"

if [ "$DRY_RUN" = 1 ]; then
  say "Simulación: no se compila ni se sube nada."
  echo "  xcodebuild archive -scheme AppPersonal -destination generic/platform=iOS \\"
  echo "    -archivePath $ARCHIVE CURRENT_PROJECT_VERSION=$BUILD_NUMBER <clave>"
  echo "  xcodebuild -exportArchive -archivePath $ARCHIVE -exportPath $EXPORT_DIR <clave>"
  exit 0
fi

say "Archivando"
xcodebuild archive \
  -project AppPersonal.xcodeproj \
  -scheme AppPersonal \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${AUTH[@]}"

say "Firmando y subiendo a App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS" \
  "${AUTH[@]}"

say "Subida $VERSION ($BUILD_NUMBER). App Store Connect tarda unos minutos en procesarla;"
say "después aparece en TestFlight para los testers internos, sin revisión de Apple."
