#!/usr/bin/env bash
# Banc de test : la VRAIE configuration (nginx/, scripts/) dans le vrai conteneur SWAG, devant de faux services,
# avec un certificat de test déjà en place. Vérifie : génération des sites, contrôle du certificat par new-site.sh,
# redirection HTTPS, refus d'un nom inconnu, en-têtes, WebSocket, services en HTTPS auto-signé, en-têtes volumineux,
# et surtout qu'un service arrêté n'empêche pas Nginx de démarrer.
#
# Usage : ./tests/run.sh          Prérequis : Docker, bash, curl. Ne touche ni aux sites ni aux certificats réels.
# Non testé ici : l'obtention et le renouvellement Let's Encrypt (domaine réel, accessible depuis Internet).
# shellcheck disable=SC2015,SC2086  # « test && ok || ko » : ok réussit toujours ; DC_ARGS contient plusieurs mots
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
GEN="$HERE/.generated"
APP=app.test.example; KC=id.test.example; VM=vm.test.example; MEDIA=media.test.example
export HTTP_PORT=18080 HTTPS_PORT=18443 PROXY_NETWORK=proxy-test
export URL=$APP SUBDOMAINS="" EXTRA_DOMAINS="$KC,$VM,$MEDIA" EMAIL=test@test.example STAGING=false
HP=$HTTP_PORT SP=$HTTPS_PORT

PASS=0; FAIL=0
ok() { echo "  [OK]    $1"; PASS=$((PASS + 1)); }
ko() { echo "  [ECHEC] $1"; FAIL=$((FAIL + 1)); }
host_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
DC_ARGS="-p proxy-test --project-directory $ROOT -f $ROOT/docker-compose.yml -f $HERE/compose.override.yaml"
dc() { docker compose $DC_ARGS "$@"; }
cleanup() { dc down -v >/dev/null 2>&1; }
trap cleanup EXIT
command -v docker >/dev/null || { echo "Docker introuvable." >&2; exit 1; }

req() { local h=$1 path=$2; shift 2; curl -sk --resolve "$h:$SP:127.0.0.1" "$@" "https://$h:$SP$path"; }
has() { grep -q -F -- "$2" <<<"$1"; }

echo "== Préparation"
rm -rf "$GEN"; mkdir -p "$GEN/sites" "$GEN/sites-check"
MSYS_NO_PATHCONV=1 docker run --rm -e URL="$APP" -e SANS="$APP $KC $VM $MEDIA" -v "$(host_path "$GEN"):/out" alpine sh -c '
  apk add -q openssl >/dev/null
  mkdir -p /out/backend-certs "/out/config/etc/letsencrypt/live/$URL"
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout /out/backend-certs/backend.key -out /out/backend-certs/backend.crt -subj /CN=service-interne 2>/dev/null
  ext=""; for d in $SANS; do ext="$ext,DNS:$d"; done
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "/out/config/etc/letsencrypt/live/$URL/privkey.pem" \
    -out "/out/config/etc/letsencrypt/live/$URL/fullchain.pem" -subj "/CN=$URL" -addext "subjectAltName=${ext#,}" 2>/dev/null
  chmod -R a+rX /out' || { echo "génération des certificats impossible" >&2; exit 1; }

echo "== scripts/new-site.sh"
NS() { SITES_DIR="$GEN/sites" SKIP_CERT_CHECK=1 bash "$ROOT/scripts/new-site.sh" "$@" >/dev/null 2>&1; }
NS app "$APP" app:3000 && ok "site créé d'après le modèle app" || ko "création du site app"
NS keycloak "$KC" keycloak:8080 && ok "site créé d'après le modèle keycloak" || ko "création du site keycloak"
NS hyperviseur "$VM" esxi:443 && ok "site créé d'après le modèle hyperviseur" || ko "création du site hyperviseur"
NS plex "$MEDIA" plex:32400 && ok "site créé d'après le modèle plex" || ko "création du site plex"
NS app "$APP" app:3000 && ko "un site existant a été écrasé" || ok "un site déjà existant n'est pas écrasé"
NS inconnu autre.test.example x:1 && ko "modèle inconnu accepté" || ok "modèle inconnu refusé"
NS app "Pas Valide" x:1 && ko "domaine invalide accepté" || ok "domaine invalide refusé"
NS app autre.test.example sansport && ko "service sans port accepté" || ok "service sans port refusé"
grep -q "__DOMAIN__\|__UPSTREAM__" "$GEN"/sites/*.conf && ko "des repères __...__ subsistent dans les sites générés" || ok "tous les repères sont remplacés dans les sites générés"
grep -q "ssl_certificate " "$GEN"/sites/*.conf && ko "un site déclare son propre certificat" || ok "les sites utilisent le certificat de SWAG (ssl.conf)"

echo "== Démarrage de SWAG"
dc up -d >/dev/null 2>&1 || { echo "démarrage impossible" >&2; dc logs --tail 20 >&2; exit 1; }
for _ in $(seq 1 120); do req "$APP" /echo -o /dev/null && break; sleep 1; done
dc exec -T swag nginx -t >/dev/null 2>&1 && ok "nginx -t valide" || ko "nginx -t en échec"
dc logs swag 2>&1 | grep -q "Certificate exists; parameters unchanged" && ok "SWAG reconnaît le certificat en place (aucune demande à Let's Encrypt)" || ko "SWAG ne reconnaît pas le certificat de test"
health=starting; for _ in $(seq 1 90); do health=$(docker inspect -f '{{.State.Health.Status}}' swag-test 2>/dev/null); [[ "$health" == healthy ]] && break; sleep 1; done
[[ "$health" == healthy ]] && ok "conteneur SWAG en bonne santé (healthcheck)" || ko "conteneur SWAG : état $health"

echo "== new-site.sh : contrôle du certificat de SWAG"
CHK() { SITES_DIR="$GEN/sites-check" COMPOSE_CMD="docker compose $DC_ARGS" bash "$ROOT/scripts/new-site.sh" "$@" >/dev/null 2>&1; }
CHK app "$KC" app:3000 && ok "site accepté : le domaine figure dans le certificat" || ko "site refusé alors que le domaine est dans le certificat"
CHK app hors-certificat.test.example app:3000 && ko "site créé pour un domaine absent du certificat" || ok "site refusé : domaine absent du certificat"

echo "== Ports 80 et 443 par défaut"
r=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H "Host: $APP" "http://127.0.0.1:$HP/page?x=1")
[[ "$r" == "301 https://$APP/page?x=1" ]] && ok "HTTP redirigé vers HTTPS (301), chemin et paramètres conservés" || ko "redirection HTTP : $r"
curl -sk --resolve "inconnu.test.example:$SP:127.0.0.1" "https://inconnu.test.example:$SP/" -o /dev/null 2>/dev/null && ko "un nom inconnu a reçu une réponse" || ok "nom inconnu refusé dès la poignée de main TLS"
curl -sk "https://127.0.0.1:$SP/" -o /dev/null 2>/dev/null && ko "l'adresse IP seule a reçu une réponse" || ok "adresse IP seule refusée"

echo "== Site app (HTTP, WebSocket)"
out=$(req "$APP" /echo)
has "$out" '"backend":"app"' && ok "atteint le bon service" || ko "mauvais service : ${out:0:100}"
has "$out" '"x-forwarded-proto":"https"' && ok "X-Forwarded-Proto: https" || ko "X-Forwarded-Proto absent"
has "$out" "\"host\":\"$APP\"" && ok "en-tête Host conservé" || ko "en-tête Host modifié"
has "$out" '"x-forwarded-for"' && has "$out" '"x-real-ip"' && ok "X-Forwarded-For et X-Real-IP" || ko "adresse du client non transmise"
hdr=$(req "$APP" /echo -D - -o /dev/null)
has "$hdr" "Strict-Transport-Security" && ok "HSTS présent" || ko "HSTS absent"
grep -qi '^server: nginx/' <<<"$hdr" && ko "la version de Nginx est annoncée" || ok "la version de Nginx n'est pas annoncée"
ws=$(req "$APP" /socket -i --http1.1 --max-time 3 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' 2>/dev/null || true)
has "$ws" "101 Switching Protocols" && ok "WebSocket accepté (101)" || ko "WebSocket refusé : ${ws:0:80}"

echo "== Site keycloak (en-têtes volumineux)"
out=$(req "$KC" /echo -H "X-Gros: $(head -c 12000 /dev/zero | tr '\0' a)")
has "$out" '"backend":"keycloak"' && ok "un en-tête de 12 Ko passe (large_client_header_buffers)" || ko "en-tête volumineux refusé : ${out:0:100}"
has "$out" '"x-forwarded-host"' && has "$out" '"x-forwarded-port"' && ok "X-Forwarded-Host et X-Forwarded-Port" || ko "X-Forwarded-Host/Port absents"

echo "== Services joints en HTTPS auto-signé"
out=$(req "$VM" /echo)
has "$out" '"backend":"esxi"' && has "$out" '"secure":true' && ok "hyperviseur : saut HTTPS auto-signé accepté" || ko "hyperviseur : ${out:0:100}"
big=$(mktemp); head -c 60000000 /dev/zero > "$big"
code=$(req "$VM" /upload -X POST --data-binary @"$big" -o /dev/null -w '%{http_code}'); rm -f "$big"
[[ "$code" == 200 ]] && ok "hyperviseur : envoi de 60 Mo accepté (client_max_body_size 0)" || ko "hyperviseur : envoi de 60 Mo : HTTP $code"
out=$(req "$MEDIA" /echo)
has "$out" '"backend":"plex"' && has "$out" '"secure":true' && ok "plex : saut HTTPS auto-signé accepté" || ko "plex : ${out:0:100}"
t=$(req "$MEDIA" /slow -o /dev/null -w '%{time_starttransfer} %{time_total}')
awk -v a="${t%% *}" -v b="${t##* }" 'BEGIN{exit !(a<1.0 && b>=2.0)}' && ok "plex : réponse diffusée sans mise en mémoire tampon" || ko "plex : réponse mise en mémoire tampon ($t)"

echo "== Un service arrêté n'empêche pas Nginx de démarrer"
dc stop app >/dev/null 2>&1
code=$(req "$APP" /echo -o /dev/null -w '%{http_code}')
[[ "$code" == 502 ]] && ok "service arrêté : 502" || ko "service arrêté : HTTP $code (502 attendu)"
has "$(req "$APP" /echo)" "momentanément indisponible" && ok "page d'erreur du proxy affichée" || ko "page d'erreur absente"
dc restart swag >/dev/null 2>&1
for _ in $(seq 1 120); do req "$KC" /echo -o /dev/null && break; sleep 1; done
has "$(req "$KC" /echo)" '"backend":"keycloak"' && ok "SWAG redémarre avec un service arrêté ; les autres sites répondent" || ko "SWAG ne redémarre pas avec un service arrêté"
dc start app >/dev/null 2>&1
code=000; for _ in $(seq 1 30); do code=$(req "$APP" /echo -o /dev/null -w '%{http_code}'); [[ "$code" == 200 ]] && break; sleep 1; done
[[ "$code" == 200 ]] && ok "service relancé : le site répond de nouveau sans recharger Nginx" || ko "service relancé : HTTP $code"

echo; echo "Reverse proxy : $PASS réussi(s), $FAIL échec(s)"
[[ $FAIL -eq 0 ]]
