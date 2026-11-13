#!/usr/bin/env bash
# Crée un site : nginx/sites/<domaine>.conf, d'après un modèle de nginx/templates/.
#
# Usage   : ./scripts/new-site.sh <modèle> <domaine> <hôte:port>
# Exemple : ./scripts/new-site.sh app app.exemple.fr mon-app:3000
#
#   modèle    un fichier de nginx/templates/ sans son extension (app, app-https, keycloak, hyperviseur, plex)
#   domaine   le nom public du site ; son DNS doit pointer vers ce serveur
#   hôte:port le service derrière le proxy : nom de son conteneur (sur le réseau « proxy ») et son port interne,
#             ou une adresse joignable depuis ce serveur
#
# Le domaine doit déjà figurer dans le certificat de SWAG (SUBDOMAINS ou EXTRA_DOMAINS du .env, puis
# « docker compose up -d » pour redemander le certificat) : un site sans certificat valide fait avertir les navigateurs.
# Variables : SITES_DIR (défaut nginx/sites), COMPOSE_CMD (défaut « docker compose »), SKIP_CERT_CHECK=1 (tests).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL_DIR="$ROOT/nginx/templates"
SITES_DIR="${SITES_DIR:-$ROOT/nginx/sites}"
COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

die() { echo "Erreur : $*" >&2; exit 1; }

models() { find "$TPL_DIR" -maxdepth 1 -name '*.conf' -exec basename {} .conf \; | sort | tr '\n' ' '; }

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  echo
  echo "Modèles disponibles : $(models)"
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ $# -eq 3 ]] || { usage >&2; exit 2; }

MODEL=$1 DOMAIN=$2 UPSTREAM=$3
TEMPLATE="$TPL_DIR/$MODEL.conf"
TARGET="$SITES_DIR/$DOMAIN.conf"

[[ "$MODEL" =~ ^[a-z0-9-]+$ && -f "$TEMPLATE" ]] || die "modèle inconnu « $MODEL ». Disponibles : $(models)"
[[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || die "domaine invalide « $DOMAIN » (minuscules, chiffres, tirets et points)."
[[ "$UPSTREAM" =~ ^[A-Za-z0-9._-]+:[0-9]{1,5}$ ]] || die "service invalide « $UPSTREAM » : attendu hôte:port, par exemple mon-app:3000."
[[ ! -e "$TARGET" ]] || die "$TARGET existe déjà : le supprimer ou le modifier à la main."

# Le certificat de SWAG couvre une liste de noms : on vérifie que le domaine y figure avant d'écrire le site.
if [[ "${SKIP_CERT_CHECK:-0}" != "1" ]]; then
  # shellcheck disable=SC2086  # COMPOSE_CMD contient plusieurs mots
  names=$(cd "$ROOT" && MSYS_NO_PATHCONV=1 $COMPOSE_CMD exec -T swag openssl x509 -noout -ext subjectAltName -in /config/keys/letsencrypt/fullchain.pem 2>/dev/null) \
    || die "impossible de lire le certificat de SWAG (conteneur arrêté, ou certificat pas encore obtenu). Faire : docker compose up -d"
  if ! tr ',' '\n' <<<"$names" | sed 's/^ *DNS://; s/ *$//' | grep -qxF "$DOMAIN"; then
    die "$DOMAIN ne figure pas dans le certificat de SWAG. L'ajouter à SUBDOMAINS (ou EXTRA_DOMAINS) dans .env, puis : docker compose up -d"
  fi
fi

mkdir -p "$SITES_DIR"
sed -e "s/__DOMAIN__/$DOMAIN/g" -e "s/__UPSTREAM__/$UPSTREAM/g" "$TEMPLATE" > "$TARGET"

echo "Site créé : $TARGET"
echo "Suite :"
echo "  ./scripts/check.sh                                  # vérifie la configuration (nginx -t)"
echo "  docker compose exec swag nginx -s reload            # l'applique sans coupure"
