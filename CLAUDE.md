# CLAUDE.md — docker-swag

Reverse proxy **de production** pour un serveur (VPS) : SWAG (Nginx + Certbot, `linuxserver/swag`) en Docker Compose, validation
Let's Encrypt **HTTP**. Dépôt **public** (depuis le 2026-11-23) : jamais de secret dans un fichier. Ce projet a repris tout le contenu de l'ancien `docker-nginx` (modèles, scripts, banc de test).

## Règles à ne pas enfreindre

- **Aucun secret dans ce dépôt** : pas de clé d'API (l'ancien `ovh.ini` et `.env` ont été retirés ; ils restent dans l'historique, les clés
  OVH doivent être révoquées chez OVH). `.env` est versionné et **ne contient que des réglages non secrets** (détail : `docs/parametres.md`) ; un éventuel secret se donne au démarrage.
- **Pas de `proxy_pass` avec un nom de conteneur écrit en dur** : toujours `set $upstream ...;` puis `proxy_pass http://$upstream;`.
  Avec un nom en dur, Nginx résout au démarrage et refuse de démarrer si un seul projet du serveur est arrêté.
- Un seul certificat couvre `URL`, `SUBDOMAINS` et `EXTRA_DOMAINS` : un site dont le nom n'est pas dans la liste n'a pas de certificat
  valide. `new-site.sh` le refuse. Si un nom de la liste ne pointe pas vers le serveur, toute la demande échoue.
- Nginx refuse une même directive deux fois : `client_max_body_size` est déjà dans le `nginx.conf` de SWAG (ne pas le répéter dans
  `default.conf`) ; les délais communs sont dans `snippets/timeouts.conf`, qu'un modèle qui a besoin d'autres valeurs n'inclut pas.
- Ne pas modifier le `nginx.conf` de SWAG ni son `ssl.conf` : tout passe par `nginx/site-confs/default.conf` (niveau `http`), les
  snippets et les sites. Le `map $connection_upgrade` est fourni par SWAG.
- Toute modification de `nginx/`, `scripts/` ou du compose repasse par `./tests/run.sh` (35 vérifications, Docker seulement).

## Fichiers

| Fichier | Rôle |
|---|---|
| `docker-compose.yml` | SWAG ; réseau `proxy` créé par cette pile ; volume `swag_config` ; montages en lecture seule de `default.conf`, `snippets/`, `sites/`, `html/` dans `/config/nginx/` |
| `nginx/site-confs/default.conf` | remplace celui de SWAG : redirection port 80, `ssl_reject_handshake on` pour tout nom inconnu, `include` des sites |
| `nginx/snippets/` | `proxy.conf` (en-têtes, WebSocket), `timeouts.conf`, `errors.conf` (page 50x) |
| `nginx/templates/` | modèles de site, repères `__DOMAIN__` et `__UPSTREAM__` ; ils incluent `/config/nginx/ssl.conf` de SWAG |
| `scripts/new-site.sh` | écrit `nginx/sites/<domaine>.conf` ; vérifie que le domaine figure dans le certificat (`openssl` dans le conteneur) |
| `scripts/certs.sh` | `status` (noms, expiration), `test` (renouvellement à blanc) |
| `scripts/check.sh` | `nginx -t` dans le conteneur |
| `tests/` | banc : `run.sh`, `compose.override.yaml`, `backend.js` (faux service HTTP/HTTPS, WebSocket, réponse lente) |

## Limites connues

- L'obtention et le renouvellement Let's Encrypt ne sont **pas testés** (domaine réel nécessaire). Premier essai avec `STAGING=true`,
  puis `./scripts/certs.sh test`.
- En validation HTTP, SWAG **arrête Nginx quelques secondes** à chaque renouvellement (hooks `pre`/`post` de certbot). Pas de joker.
- Le healthcheck vérifie que le processus Nginx tourne, pas que les sites répondent.
- Sous Git Bash (Windows), les commandes `docker exec` avec un chemin `/config/...` exigent `MSYS_NO_PATHCONV=1` (déjà fait dans les scripts).

## Historique

Ancien projet SWAG (domaine et sous-domaines écrits en dur, clés OVH versionnées, validation DNS mal réglée) refondu en 2026-11 :
repris de `docker-nginx` (reverse proxy Nginx + Certbot séparés), qui a ensuite été retiré. Choix de la validation HTTP le 2026-11-13.
