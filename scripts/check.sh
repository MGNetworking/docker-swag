#!/usr/bin/env bash
# Vérifie la configuration de Nginx (nginx -t) dans le conteneur SWAG, qui doit tourner.
# À lancer avant chaque rechargement : un « reload » sur une configuration invalide laisse l'ancienne en place.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

docker compose ps --status running --services 2>/dev/null | grep -qx swag \
  || { echo "Erreur : SWAG ne tourne pas (docker compose up -d)." >&2; exit 1; }
docker compose exec -T swag nginx -t
