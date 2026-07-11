# RustDesk Web Client — images Docker

Ce dépôt construit et exécute le client web RustDesk selon deux variantes clairement séparées.

| Variante | Image | Port interne | Configuration runtime |
|---|---|---:|---|
| Courante | `pmietlicki/docker-rustdesk-web-client:latest` | `80` | Proxy Nginx via `BACKEND_HOST` et `PROTO` |
| Héritée v1 | `pmietlicki/docker-rustdesk-web-client:v1` | `5000` | Variables RustDesk injectées dans `localStorage` |

La variante `v1` reste disponible pour les utilisateurs qui ont besoin de fournir directement les serveurs rendez-vous, relay et API au démarrage du conteneur.

## Démarrage de la variante courante

Copiez la configuration d’exemple, puis adaptez au minimum le backend RustDesk :

```bash
cp config-examples.env .env
$EDITOR .env
docker compose up --build --detach
```

L’interface est ensuite disponible sur <http://localhost:5000>.

Le conteneur Nginx n’expose que son port HTTP `80`. Les connexions API et WebSocket sont relayées sur ce même port :

- `/api/` vers le port backend `21114` ;
- `/ws/id` vers le port backend `21118` ;
- `/ws/relay` vers le port backend `21119`.

`BACKEND_HOST` doit être un nom d’hôte ou une adresse IP joignable depuis le conteneur, sans schéma ni port. Une IPv6 doit être placée entre crochets. `PROTO` accepte uniquement `http` ou `https` et décrit la connexion entre Nginx et le backend ; la terminaison TLS publique doit être assurée par un reverse proxy ou un Ingress.

Exécution directe de l’image publiée :

```bash
docker run --detach \
  --name rustdesk-web-client \
  --publish 5000:80 \
  --env BACKEND_HOST=rustdesk.example.com \
  --env PROTO=https \
  pmietlicki/docker-rustdesk-web-client:latest
```

## Variante v1

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

| Variable | Défaut | Description |
|---|---|---|
| `CUSTOM_RENDEZVOUS_SERVER` | vide | Serveur rendez-vous avec son port |
| `RELAY_SERVER` | vide | Serveur relay avec son port |
| `API_SERVER` | `api.rustdesk.com` | Serveur API |
| `KEY` | vide | Clé publique RustDesk |
| `PORT` | `5000` | Port HTTP interne de la variante v1 |

Les valeurs sont sérialisées en JSON avant d’être écrites dans `env-config.js`, afin que les guillemets, antislashs et retours à la ligne ne puissent pas casser le JavaScript généré.

Construction locale de cette variante :

```bash
docker build --file v1/Dockerfile --tag rustdesk-web-client:v1-local .
```

## Construction locale

Le script charge automatiquement `.env` sans l’exécuter comme du code shell.

```bash
./build.sh config   # configuration effective
./build.sh image    # construire uniquement l’image
./build.sh build    # nettoyer, construire, démarrer et contrôler la santé
./build.sh status   # état Docker réel
./build.sh logs     # suivre les logs
./build.sh stop
./build.sh start
./build.sh clean
./build.sh compose  # même parcours via Docker Compose
```

Le build par défaut utilise `MonsieurBiche/rustdesk-web-client`, branche `fix-build`, verrouillée au commit indiqué dans `RUSTDESK_EXPECTED_COMMIT`. Une autre source peut être choisie avec `RUSTDESK_REPO` et `RUSTDESK_TAG`; `RUSTDESK_COMMIT` permet de verrouiller explicitement n’importe quelle source sur un SHA.

L’archive `web_deps.tar.gz` est lue depuis le checkout courant : un build d’un commit donné n’utilise donc plus silencieusement l’archive d’une autre révision de `main`.

## Configuration `.env`

Toutes les valeurs disponibles sont documentées dans [config-examples.env](config-examples.env). Les variables déjà définies dans l’environnement appelant ont priorité sur celles du fichier `.env`.

Principales valeurs :

| Variable | Défaut | Usage |
|---|---|---|
| `WEB_PORT` | `5000` | Port HTTP publié sur l’hôte |
| `BACKEND_HOST` | `127.0.0.1` | Backend des routes API/WebSocket |
| `PROTO` | `http` | Protocole du backend (`http` ou `https`) |
| `RUSTDESK_REPO` | `MonsieurBiche/rustdesk-web-client` | Dépôt source |
| `RUSTDESK_TAG` | `fix-build` | Branche ou tag source |
| `RUSTDESK_COMMIT` | vide | SHA explicite facultatif |
| `ENABLE_WSS` | `true` | Conversion des URL `ws://` en `wss://` pendant le build |
| `FLUTTER_VERSION` | `3.22.1` | Version Flutter utilisée pour compiler |
| `RUST_VERSION` | `1.97.0` | Toolchain Rust utilisée pour la cible WebAssembly |

Attention : `127.0.0.1` désigne le conteneur web lui-même. Fournissez un autre hôte si le backend RustDesk tourne dans un autre conteneur ou sur une autre machine.

## Validation

Les contrôles locaux rapides sont :

```bash
bash -n build.sh v1/server/server.sh tests/*.sh
sh -n docker/nginx/entrypoint.sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
tests/test_build_script.sh
tests/test_nginx_entrypoint.sh
docker compose config --quiet
docker build --check .
```

La CI exécute les mêmes contrôles, ainsi que ShellCheck et Hadolint.

## Kubernetes

L’exemple historique de déploiement de la variante `v1` est conservé dans [docs/KUBERNETES.md](docs/KUBERNETES.md). Il doit être adapté à l’Ingress, au stockage et aux secrets de chaque environnement.

## Dépannage

```bash
./build.sh status
docker compose ps
docker compose logs --tail=100 rustdesk-web
curl --fail http://127.0.0.1:5000/
```

Si les routes `/api/` ou `/ws/*` échouent alors que l’interface se charge, vérifiez que `BACKEND_HOST` est résolu depuis le conteneur et que les ports RustDesk concernés sont accessibles sur le réseau Docker.

## Licence

Ce dépôt suit la licence AGPL-3.0 du projet RustDesk. Consultez [LICENSE](LICENSE) ainsi que les licences incluses dans les dépendances distribuées.
