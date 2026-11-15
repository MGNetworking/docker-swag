#!/usr/bin/env bash
# Certificat Let's Encrypt de SWAG (obtenu et renouvelé par SWAG lui-même, validation HTTP).
#
# Usage :
#   ./scripts/certs.sh status   noms couverts par le certificat et date d'expiration
#   ./scripts/certs.sh test     essai de renouvellement à blanc (certbot --dry-run), sans rien modifier
#
# Le renouvellement est automatique (tâche planifiée dans SWAG) ; en validation HTTP, SWAG arrête Nginx quelques
# secondes pendant qu'il renouvelle (environ tous les 60 jours). « test » est le seul moyen de vérifier à l'avance
# qu'il fonctionnera : le lancer une fois après la première installation (il arrête aussi Nginx quelques secondes).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export MSYS_NO_PATHCONV=1   # Git Bash sous Windows : ne pas convertir les chemins /config/... passés à docker

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in
  status)
    docker compose exec -T swag sh -c \
      'openssl x509 -noout -subject -issuer -enddate -ext subjectAltName -in /config/keys/letsencrypt/fullchain.pem'
    ;;
  test)
    docker compose exec -T swag certbot renew --dry-run \
      --config-dir /config/etc/letsencrypt --logs-dir /config/log/letsencrypt --work-dir /tmp/letsencrypt \
      --config /config/etc/letsencrypt/cli.ini
    ;;
  -h|--help|"") usage ;;
  *) usage >&2; exit 2 ;;
esac
