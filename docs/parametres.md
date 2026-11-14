# Les réglages de `.env`

`.env` est lu par `docker compose` et passé à SWAG. Il ne contient **aucun secret** : SWAG n'a besoin ni de mot de passe ni de clé
d'API en validation HTTP. Il est versionné ; à modifier à la main pour chaque serveur.

## Domaines et certificat

| Variable | Rôle | À savoir |
|---|---|---|
| `URL` | domaine principal : nom du certificat | son DNS doit pointer vers ce serveur ; obligatoire |
| `SUBDOMAINS` | sous-domaines de `URL`, séparés par des virgules, **sans** le domaine (`app,keycloak` donne `app.exemple.fr` et `keycloak.exemple.fr`) | tous ajoutés au **même** certificat ; si l'un ne pointe pas encore vers le serveur, **toute la demande échoue** |
| `EXTRA_DOMAINS` | autres domaines **complets**, séparés par des virgules (`autre.fr,app.autre.fr`) | même certificat ; laisser vide s'il n'y en a pas |
| `ONLY_SUBDOMAINS` | `true` : le certificat ne couvre que les sous-domaines, pas `URL` lui-même | `false` par défaut |
| `EMAIL` | adresse pour les avis d'expiration de Let's Encrypt | obligatoire, **à renseigner** |
| `STAGING` | `true` : serveur d'essai de Let's Encrypt | le certificat obtenu n'est pas reconnu des navigateurs, mais il n'y a pas de limite de tentatives : à utiliser pour un premier essai, puis repasser à `false` |

Ajouter un site, c'est ajouter son nom à `SUBDOMAINS` ou `EXTRA_DOMAINS`, puis `docker compose up -d` : SWAG redemande le certificat avec
la nouvelle liste. Let's Encrypt limite les demandes identiques (environ 5 par semaine) : d'où `STAGING=true` pour les essais.

## Environnement du conteneur

| Variable | Rôle | Valeur par défaut |
|---|---|---|
| `TZ` | fuseau horaire des journaux et des tâches planifiées (renouvellement) | `Europe/Paris` |
| `HTTP_PORT` | port du serveur pour HTTP (redirection vers HTTPS) | `80` |
| `HTTPS_PORT` | port du serveur pour HTTPS | `443` |
| `PROXY_NETWORK` | nom du réseau Docker partagé avec les autres projets | `proxy` |

- `HTTP_PORT` et `HTTPS_PORT` : changer ces valeurs n'a de sens que pour un essai en local. Let's Encrypt n'atteint le serveur que
  par les ports **80 et 443**, et les navigateurs utilisent 443.
- `PROXY_NETWORK` : les autres projets du serveur rejoignent ce réseau (`networks: proxy: external: true`) ; le nom doit y être le même.

## Ce qui n'est pas ici

- Les **sites** (domaine, service vers lequel router) : `nginx/sites/`, créés par `./scripts/new-site.sh`.
- L'identité (UID/GID 1000) et la validation (`http`) : écrites dans `docker-compose.yml`, on ne les change pas.
- Le choix de la validation DNS (joker, sans coupure au renouvellement) : non retenu. Il demanderait des clés d'API chez le registraire
  du domaine, à fournir au démarrage et jamais écrites dans le dépôt.
