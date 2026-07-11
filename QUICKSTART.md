# Démarrage rapide

## Docker Compose

```bash
git clone https://github.com/pmietlicki/docker-rustdesk-web-client.git
cd docker-rustdesk-web-client
cp config-examples.env .env
$EDITOR .env
docker compose up --build --detach
curl --fail http://127.0.0.1:5000/
```

Dans `.env`, configurez `BACKEND_HOST` avec un hôte joignable depuis le conteneur. Le service web est publié sur `WEB_PORT` et le port interne de l’image courante est `80`.

## Script de gestion

```bash
./build.sh config
./build.sh build
./build.sh status
./build.sh logs
```

Le script propose également `image`, `start`, `stop`, `clean` et `compose`. Exécutez `./build.sh --help` pour la liste à jour.

## Variante v1 préconstruite

```bash
docker run --detach \
  --name rustdesk-web-v1 \
  --publish 5000:5000 \
  --env CUSTOM_RENDEZVOUS_SERVER=rustdesk.example.com:21116 \
  --env RELAY_SERVER=rustdesk.example.com:21117 \
  --env API_SERVER=api.example.com \
  --env KEY='votre-clé-publique' \
  pmietlicki/docker-rustdesk-web-client:v1
```

Consultez [README.md](README.md) pour les variables, les routes proxy et les procédures de validation.
