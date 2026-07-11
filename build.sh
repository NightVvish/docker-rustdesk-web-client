#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

log_info() { printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$*"; }
log_success() { printf '%b[SUCCESS]%b %s\n' "$GREEN" "$NC" "$*"; }
log_warning() { printf '%b[WARNING]%b %s\n' "$YELLOW" "$NC" "$*"; }
log_error() { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2; }

load_env_file() {
    local env_file="$1" line key value
    [[ -f "$env_file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*export[[:space:]]+ ]] && line="${line#*export }"
        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            log_error "Ligne .env invalide: $line"
            return 64
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [[ ${#value} -ge 2 ]] \
            && { [[ "$value" == \"*\" ]] || [[ "$value" == \'*\' ]]; }; then
            value="${value:1:${#value}-2}"
        fi
        if [[ ! -v "$key" ]]; then
            printf -v "$key" '%s' "$value"
            export "${key?}"
        fi
    done < "$env_file"
}

ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
load_env_file "$ENV_FILE"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.22.1}"
RUST_VERSION="${RUST_VERSION:-1.97.0}"
RUSTDESK_TAG="${RUSTDESK_TAG:-fix-build}"
RUSTDESK_REPO="${RUSTDESK_REPO:-MonsieurBiche/rustdesk-web-client}"
RUSTDESK_COMMIT="${RUSTDESK_COMMIT:-}"
RUSTDESK_EXPECTED_COMMIT="${RUSTDESK_EXPECTED_COMMIT:-525b5e561faf824850c71500adf463e4e0a504d4}"
ENABLE_WSS="${ENABLE_WSS:-true}"
IMAGE_NAME="${IMAGE_NAME:-rustdesk-web-client}"
CONTAINER_NAME="${CONTAINER_NAME:-rustdesk-web-client}"
WEB_PORT="${WEB_PORT:-5000}"
BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
PROTO="${PROTO:-http}"

COMPOSE=()

detect_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE=(docker-compose)
    else
        log_error "Docker Compose n'est pas installé"
        return 1
    fi
}

check_prerequisites() {
    command -v docker >/dev/null 2>&1 || {
        log_error "Docker n'est pas installé"
        return 1
    }
    docker info >/dev/null 2>&1 || {
        log_error "Le démon Docker n'est pas accessible"
        return 1
    }
    local available_space
    available_space="$(df -Pk . | awk 'NR == 2 {print $4}')"
    if (( available_space < 4194304 )); then
        log_warning "Espace disque disponible inférieur à 4 Gio"
    fi
}

container_exists() {
    docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

cleanup() {
    if container_exists; then
        log_info "Suppression du conteneur $CONTAINER_NAME"
        docker rm --force "$CONTAINER_NAME" >/dev/null
    fi
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        log_info "Suppression de l'image $IMAGE_NAME"
        docker image rm "$IMAGE_NAME" >/dev/null
    fi
    log_success "Nettoyage terminé"
}

build_image() {
    local -a build_args=(
        --build-arg "FLUTTER_VERSION=$FLUTTER_VERSION"
        --build-arg "RUST_VERSION=$RUST_VERSION"
        --build-arg "RUSTDESK_TAG=$RUSTDESK_TAG"
        --build-arg "RUSTDESK_REPO=$RUSTDESK_REPO"
        --build-arg "RUSTDESK_COMMIT=$RUSTDESK_COMMIT"
        --build-arg "RUSTDESK_EXPECTED_COMMIT=$RUSTDESK_EXPECTED_COMMIT"
        --build-arg "ENABLE_WSS=$ENABLE_WSS"
    )

    log_info "Build $RUSTDESK_REPO@$RUSTDESK_TAG avec Flutter $FLUTTER_VERSION"
    DOCKER_BUILDKIT=1 docker build \
        "${build_args[@]}" \
        --progress=plain \
        --tag "$IMAGE_NAME" \
        .
    log_success "Image construite: $IMAGE_NAME"
}

create_container() {
    if container_exists; then
        log_error "Le conteneur $CONTAINER_NAME existe déjà; utilisez 'start' ou 'clean'"
        return 1
    fi

    docker run --detach \
        --name "$CONTAINER_NAME" \
        --publish "$WEB_PORT:80" \
        --env "BACKEND_HOST=$BACKEND_HOST" \
        --env "PROTO=$PROTO" \
        --restart unless-stopped \
        "$IMAGE_NAME" >/dev/null
    log_success "Conteneur créé: $CONTAINER_NAME"
}

start_container() {
    if container_exists; then
        docker start "$CONTAINER_NAME" >/dev/null
        log_success "Conteneur démarré: $CONTAINER_NAME"
    else
        create_container
    fi
}

health_check() {
    local attempt
    command -v curl >/dev/null 2>&1 || {
        log_error "curl est requis pour le contrôle de santé local"
        return 1
    }
    for attempt in {1..30}; do
        if (( attempt == 1 )); then
            log_info "Attente du service sur le port $WEB_PORT"
        fi
        if curl --fail --silent --show-error \
            "http://127.0.0.1:$WEB_PORT/" >/dev/null 2>&1; then
            log_success "Service accessible sur http://127.0.0.1:$WEB_PORT"
            return 0
        fi
        sleep 2
    done
    log_error "Service inaccessible après 60 secondes"
    docker logs --tail 50 "$CONTAINER_NAME" >&2 || true
    return 1
}

show_config() {
    cat <<EOF
Image              : $IMAGE_NAME
Conteneur           : $CONTAINER_NAME
Port web            : $WEB_PORT -> 80
Backend RustDesk    : $BACKEND_HOST
Protocole backend   : $PROTO
Dépôt source        : $RUSTDESK_REPO
Référence source    : $RUSTDESK_TAG
Commit explicite    : ${RUSTDESK_COMMIT:-<automatique>}
Commit stable       : $RUSTDESK_EXPECTED_COMMIT
Flutter             : $FLUTTER_VERSION
Rust                : $RUST_VERSION
Conversion WSS      : $ENABLE_WSS
EOF
}

show_status() {
    if ! container_exists; then
        log_error "Le conteneur $CONTAINER_NAME n'existe pas"
        return 1
    fi

    local state health image ports
    state="$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME")"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}non configuré{{end}}' "$CONTAINER_NAME")"
    image="$(docker inspect --format '{{.Config.Image}}' "$CONTAINER_NAME")"
    ports="$(docker port "$CONTAINER_NAME" 80/tcp 2>/dev/null || true)"

    printf 'Conteneur : %s\nImage     : %s\nÉtat      : %s\nSanté     : %s\nPort web  : %s\n' \
        "$CONTAINER_NAME" "$image" "$state" "$health" "${ports:-non publié}"
}

compose_up() {
    detect_compose
    "${COMPOSE[@]}" config --quiet
    "${COMPOSE[@]}" up --build --detach
    health_check
}

usage() {
    cat <<EOF
Usage: $0 COMMAND

Commandes:
  build    Nettoyer, construire l'image et démarrer le conteneur
  image    Construire uniquement l'image
  start    Démarrer le conteneur existant, ou le créer depuis l'image
  stop     Arrêter le conteneur
  logs     Suivre les logs du conteneur
  status   Afficher l'état Docker réel
  config   Afficher la configuration effective
  compose  Construire et démarrer avec Docker Compose
  clean    Supprimer le conteneur et l'image locale
EOF
}

run_command() {
    local command="${1:-}"
    case "$command" in
        build)
            check_prerequisites
            cleanup
            build_image
            create_container
            health_check
            ;;
        image)
            check_prerequisites
            build_image
            ;;
        start)
            check_prerequisites
            start_container
            health_check
            ;;
        stop)
            check_prerequisites
            container_exists && docker stop "$CONTAINER_NAME" >/dev/null
            ;;
        logs)
            check_prerequisites
            docker logs --follow "$CONTAINER_NAME"
            ;;
        status)
            command -v docker >/dev/null 2>&1 || return 1
            show_status
            ;;
        config)
            show_config
            ;;
        compose)
            check_prerequisites
            compose_up
            ;;
        clean)
            check_prerequisites
            cleanup
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            usage >&2
            return 64
            ;;
    esac
}

show_menu() {
    cat <<'EOF'

RustDesk Web Client
1. Build complet
2. Build de l'image uniquement
3. Démarrer
4. Arrêter
5. Logs
6. Statut
7. Configuration
8. Docker Compose
9. Nettoyage
0. Quitter
EOF
}

interactive_menu() {
    local choice
    while true; do
        show_menu
        read -r -p "Choisissez une option [0-9]: " choice
        case "$choice" in
            1) run_command build ;;
            2) run_command image ;;
            3) run_command start ;;
            4) run_command stop ;;
            5) run_command logs ;;
            6) run_command status ;;
            7) run_command config ;;
            8) run_command compose ;;
            9) run_command clean ;;
            0) return 0 ;;
            *) log_error "Option invalide" ;;
        esac
    done
}

trap 'log_error "Script interrompu"; exit 130' INT TERM

if (( $# == 0 )); then
    interactive_menu
else
    if (( $# != 1 )); then
        usage >&2
        exit 64
    fi
    run_command "$1"
fi
