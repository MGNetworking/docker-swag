# docker-swag : reverse proxy de production (SWAG)

Un reverse proxy **Nginx** en HTTPS, avec son certificat **Let's Encrypt** obtenu et renouvelé par **SWAG** (image
`linuxserver/swag` : Nginx + Certbot dans un seul conteneur). À poser une fois sur un serveur pour exposer les autres
projets qui y tournent : chacun reste dans sa pile Docker, le proxy les joint par le nom de leur conteneur et porte seul
les ports 80 et 443. Dépôt **public** (depuis le 2026-11-23) : aucun secret dedans. **Mis de côté** le 2026-11-23 : sur le VPS, k3s fait le reverse proxy et les certificats.

```
Internet ─ 80/443 ─> [ SWAG : Nginx + Certbot ] ──réseau « proxy »──> app:3000      (un conteneur par projet)
                                                                       keycloak:8080
                                                                       ...
```

## Ce que contient le dépôt

```
docker-compose.yml       SWAG
.env                     domaine, sous-domaines, adresse pour Let's Encrypt, ports (aucun secret ; détail : docs/parametres.md)
nginx/
├── site-confs/default.conf   remplace celui de SWAG : redirection HTTPS, nom inconnu refusé, charge nginx/sites/
├── snippets/                 blocs partagés : proxy (en-têtes, WebSocket), timeouts, errors
├── templates/                modèles de site : app, app-https, keycloak, hyperviseur, plex
└── sites/                    les sites de CE serveur (créés par new-site.sh ; versionnés)
html/50x.html            page d'erreur quand un service est arrêté
docs/parametres.md       le rôle de chaque réglage de .env
scripts/                 new-site.sh, check.sh, certs.sh
tests/run.sh             banc de test (Docker seulement)
```

## Démarrer sur un serveur

Prérequis : Docker avec le plugin Compose ; le DNS de **chaque** nom pointe vers le serveur ; les ports 80 et 443 sont
ouverts (pare-feu compris).

```bash
docker compose up -d     # après avoir renseigné URL, SUBDOMAINS et EMAIL dans .env (aucun mot de passe : voir docs/parametres.md) ; SWAG demande le certificat (STAGING=true pour un premier essai), puis démarre Nginx
docker compose logs -f swag
```

Le réseau Docker `proxy` est créé par cette pile : **la démarrer avant** les projets qui le rejoignent.

## Un certificat, une liste de noms

SWAG demande **un seul certificat** qui couvre `URL`, les `SUBDOMAINS` (sans le domaine) et les `EXTRA_DOMAINS` (domaines
complets). Si un seul nom ne pointe pas encore vers le serveur, **toute la demande échoue**. Ajouter un site, c'est :

1. ajouter son nom à `SUBDOMAINS` ou `EXTRA_DOMAINS` dans `.env` ;
2. `docker compose up -d` : SWAG redemande le certificat avec la nouvelle liste ;
3. créer le site.

## Ajouter un site

```bash
./scripts/new-site.sh app app.exemple.fr mon-app:3000      # <modèle> <domaine> <conteneur:port>
./scripts/check.sh                                         # nginx -t
docker compose exec swag nginx -s reload                   # l'appliquer, sans coupure
```

`new-site.sh` refuse un domaine absent du certificat. Le site créé (`nginx/sites/<domaine>.conf`) se versionne.

Brancher l'application sur le réseau du proxy, **sans publier de port** :

```yaml
services:
  mon-app:
    image: ...
    networks: [proxy]

networks:
  proxy:
    external: true
```

### Les modèles

| Modèle | Pour | Particularités |
|---|---|---|
| `app` | une application web qui parle HTTP | WebSocket géré |
| `app-https` | un service qui parle HTTPS avec un certificat interne ou auto-signé | certificat du service non vérifié |
| `keycloak` | Keycloak | tampons d'en-têtes élargis ; côté Keycloak : `KC_PROXY_HEADERS=xforwarded`, `KC_HTTP_ENABLED=true`, `KC_HOSTNAME` |
| `hyperviseur` | VMware ESXi (interface web et consoles) | HTTPS auto-signé, envois sans limite, délais très longs |
| `plex` | Plex Media Server | HTTPS, pas de mise en mémoire tampon, délais longs |

Un nouveau type de service : un fichier dans `nginx/templates/` avec les repères `__DOMAIN__` et `__UPSTREAM__`.

## Certificat

- `./scripts/certs.sh status` : noms couverts et date d'expiration ; `./scripts/certs.sh test` : renouvellement à blanc.
- **Validation HTTP** : pour renouveler (environ tous les 60 jours), SWAG **arrête Nginx quelques secondes**. Pas de certificat
  joker. La validation DNS (OVH) éviterait cette coupure et permettrait un joker, au prix de clés d'API OVH sur le serveur :
  non retenue.
- En lançant le conteneur, vous acceptez les conditions d'utilisation de Let's Encrypt.

## Ce qui est choisi

- **Un nom inconnu, ou l'adresse IP seule, est refusé dès la poignée de main TLS** : le serveur ne révèle aucun site.
- **Un service arrêté ne fait pas tomber le proxy** : les noms de conteneurs sont résolus à chaque requête (variable dans
  `proxy_pass`, DNS de Docker). Un site dont le service est arrêté répond 502 avec une page claire, les autres continuent, et
  Nginx redémarre sans erreur.
- TLS et HSTS par la configuration de SWAG (`ssl.conf`), version de Nginx masquée.
- `.env` ne contient **aucun secret** (il est versionné) ; l'état de SWAG (certificat, journaux) vit dans le volume Docker `swag_config`.

## Mettre à jour

```bash
docker compose pull && docker compose up -d        # nouvelle image SWAG ; sites et certificat sont conservés
```

## Tester

```bash
./tests/run.sh
```

Lance la vraie configuration dans le vrai conteneur SWAG, devant de faux services, avec un certificat de test déjà en place :
génération des sites, contrôle du certificat par `new-site.sh`, redirection HTTPS, refus d'un nom inconnu, en-têtes, WebSocket,
services en HTTPS auto-signé, en-têtes volumineux, envois de 60 Mo, arrêt puis redémarrage d'un service. Il ne touche ni aux
sites ni aux certificats réels.

**Non testé ici** : l'obtention et le renouvellement du certificat avec Let's Encrypt (ils demandent un vrai domaine et un
serveur joignable depuis Internet). Premier essai avec `STAGING=true`, puis `./scripts/certs.sh test`.

## Migrer depuis l'ancienne version

L'ancien compose gardait l'état dans `./config` et déclarait ses variables autrement. Ici : variables `URL`, `SUBDOMAINS`, `EMAIL`
dans `.env`, état dans le volume `swag_config` (le certificat est donc redemandé au premier démarrage). Arrêter l'ancienne pile
avant de démarrer celle-ci (mêmes ports 80 et 443).
