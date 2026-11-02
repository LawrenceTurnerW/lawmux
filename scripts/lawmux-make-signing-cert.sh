#!/usr/bin/env bash
# Create the self-signed code-signing certificate "lawmux" in the login
# keychain and trust it for code signing. scripts/lawmux-build-release.sh signs
# with it when present, so every build carries the same signing identity and
# macOS keeps the permissions granted to lawmux (Accessibility, Screen
# Recording, Automation, Input Monitoring) across reinstalls. Ad-hoc signatures
# change with every build, and macOS treats each one as a new app.
#
#   scripts/lawmux-make-signing-cert.sh            create it (no-op when present)
#   scripts/lawmux-make-signing-cert.sh --remove   delete the identity again
#
# Trusting the certificate opens a macOS password dialog once. Nothing leaves
# this Mac: the certificate is self-signed and needs no Apple developer account.
# Run it on each Mac that builds lawmux; the certificates need not match.
set -euo pipefail

NAME="lawmux"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if [[ "${1:-}" == "--remove" ]]; then
  while security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; do
    security delete-identity -c "$NAME" "$KEYCHAIN"
  done
  echo "removed $NAME"
  exit 0
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "$NAME already exists in the login keychain; nothing to do"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > req.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "==> Generating a 2048-bit RSA key and a 10-year self-signed certificate"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config req.cnf -keyout key.pem -out cert.pem 2>/dev/null
# The export password only protects the file for the seconds it exists here.
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" \
  -passout pass:lawmux -out "$NAME.p12"

echo "==> Importing into the login keychain (codesign may use it without asking)"
security import "$NAME.p12" -k "$KEYCHAIN" -P lawmux \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild >/dev/null

echo "==> Trusting it for code signing (macOS asks for your password once)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" cert.pem

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "==> $NAME is ready; the next scripts/lawmux-build-release.sh signs with it"
  echo "    (macOS asks for lawmux's permissions one more time, then keeps them)"
else
  echo "error: $NAME is not a valid code-signing identity after import" >&2
  exit 1
fi
