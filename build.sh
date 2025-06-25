#!/bin/bash

# Script de build automatisé pour RustDesk Web Client
# Version optimisée avec Flutter 3.19.6

set -e  # Arrêt en cas d'erreur

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration flexible
FLUTTER_VERSION="3.22.3"
RUSTDESK_BRANCH="${RUSTDESK_BRANCH:-enable-wss}"  # fix-build, enable-wss, add-features
RUSTDESK_REPO="${RUSTDESK_REPO:-MonsieurBiche/rustdesk-web-client}"
ENABLE_WSS="${ENABLE_WSS:-true}"
IMAGE_NAME="rustdesk-web-client"
CONTAINER_NAME="rustdesk-web-client"
WEB_PORT="5000"
WS_PORT="21117"

# Fonctions utilitaires
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérification des prérequis
check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker n'est pas installé"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_warning "Docker Compose non trouvé, utilisation de 'docker compose'"
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi
    
    # Vérifier l'espace disque (minimum 4GB)
    AVAILABLE_SPACE=$(df . | tail -1 | awk '{print $4}')
    if [ "$AVAILABLE_SPACE" -lt 4194304 ]; then  # 4GB en KB
        log_warning "Espace disque faible (< 4GB). Le build pourrait échouer."
    fi
    
    log_success "Prérequis vérifiés"
}

# Nettoyage des ressources Docker
cleanup() {
    log_info "Nettoyage des ressources Docker..."
    
    # Arrêter et supprimer le conteneur existant
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        log_info "Arrêt du conteneur existant..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    fi
    
    # Supprimer l'image existante
    if docker images | grep -q "$IMAGE_NAME"; then
        log_info "Suppression de l'image existante..."
        docker rmi "$IMAGE_NAME" 2>/dev/null || true
    fi
    
    log_success "Nettoyage terminé"
}

# Build de l'image Docker
build_image() {
    log_info "Démarrage du build Docker..."
    echo "🔧 Building RustDesk Web Client with Flutter $FLUTTER_VERSION..."
    log_info "Repository: $RUSTDESK_REPO | Branch: $RUSTDESK_BRANCH | WSS: $ENABLE_WSS"
    
    # Activer BuildKit pour de meilleures performances
    export DOCKER_BUILDKIT=1
    
    # Build avec progress et cache
    docker build \
        --build-arg FLUTTER_VERSION="$FLUTTER_VERSION" \
        --build-arg RUSTDESK_BRANCH="$RUSTDESK_BRANCH" \
        --build-arg RUSTDESK_REPO="$RUSTDESK_REPO" \
        --build-arg ENABLE_WSS="$ENABLE_WSS" \
        --progress=plain \
        --tag "$IMAGE_NAME" \
        . || {
        log_error "Échec du build Docker"
        exit 1
    }
    
    log_success "Build Docker terminé avec succès"
}

# Démarrage du conteneur
start_container() {
    log_info "Démarrage du conteneur..."
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$WEB_PORT:5000" \
        -p "$WS_PORT:21117" \
        --restart unless-stopped \
        "$IMAGE_NAME" || {
        log_error "Échec du démarrage du conteneur"
        exit 1
    }
    
    log_success "Conteneur démarré: $CONTAINER_NAME"
}

# Vérification de la santé du service
health_check() {
    log_info "Vérification de la santé du service..."
    
    # Attendre que le service soit prêt
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "http://localhost:$WEB_PORT/" > /dev/null 2>&1; then
            log_success "Service accessible sur http://localhost:$WEB_PORT"
            return 0
        fi
        
        log_info "Tentative $attempt/$max_attempts - En attente..."
        sleep 2
        ((attempt++))
    done
    
    log_error "Service non accessible après $max_attempts tentatives"
    return 1
}

# Affichage des logs
show_logs() {
    log_info "Affichage des logs (Ctrl+C pour quitter)..."
    docker logs -f "$CONTAINER_NAME"
}

# Affichage des informations de statut
show_status() {
    echo
    log_success "=== RustDesk Web Client - Statut ==="
    echo -e "${GREEN}✅ Image:${NC} $IMAGE_NAME"
    echo -e "${GREEN}✅ Conteneur:${NC} $CONTAINER_NAME"
    echo -e "${GREEN}✅ Web UI:${NC} http://localhost:$WEB_PORT"
    echo -e "${GREEN}✅ WebSocket:${NC} ws://localhost:$WS_PORT"
    echo -e "${GREEN}✅ Flutter:${NC} $FLUTTER_VERSION"
    echo -e "${GREEN}✅ RustDesk:${NC} $RUSTDESK_TAG"
    echo
    echo -e "${BLUE}Commandes utiles:${NC}"
    echo "  docker logs $CONTAINER_NAME          # Voir les logs"
    echo "  docker exec -it $CONTAINER_NAME bash # Accès shell"
    echo "  docker stop $CONTAINER_NAME          # Arrêter"
    echo "  docker start $CONTAINER_NAME         # Redémarrer"
    echo
}

# Menu principal
show_menu() {
    echo
    echo -e "${BLUE}=== RustDesk Web Client - Build Script ===${NC}"
    echo "1. Build complet (nettoyage + build + démarrage)"
    echo "2. Build seulement"
    echo "3. Démarrer le conteneur existant"
    echo "4. Arrêter le conteneur"
    echo "5. Voir les logs"
    echo "6. Statut"
    echo "7. Nettoyage"
    echo "8. Build avec Docker Compose"
    echo "0. Quitter"
    echo
    read -p "Choisissez une option [0-8]: " choice
}

# Gestion des options
handle_choice() {
    case $choice in
        1)
            check_prerequisites
            cleanup
            build_image
            start_container
            health_check && show_status
            ;;
        2)
            check_prerequisites
            build_image
            ;;
        3)
            start_container
            health_check && show_status
            ;;
        4)
            log_info "Arrêt du conteneur..."
            docker stop "$CONTAINER_NAME" 2>/dev/null || log_warning "Conteneur non trouvé"
            log_success "Conteneur arrêté"
            ;;
        5)
            show_logs
            ;;
        6)
            show_status
            ;;
        7)
            cleanup
            ;;
        8)
            check_prerequisites
            log_info "Build avec Docker Compose..."
            $DOCKER_COMPOSE down 2>/dev/null || true
            $DOCKER_COMPOSE up --build -d
            health_check && show_status
            ;;
        0)
            log_info "Au revoir!"
            exit 0
            ;;
        *)
            log_error "Option invalide"
            ;;
    esac
}

# Script principal
main() {
    # Si des arguments sont passés, exécuter directement
    if [ $# -gt 0 ]; then
        case $1 in
            "build")
                check_prerequisites
                cleanup
                build_image
                start_container
                health_check && show_status
                ;;
            "start")
                start_container
                health_check && show_status
                ;;
            "stop")
                docker stop "$CONTAINER_NAME" 2>/dev/null || true
                ;;
            "logs")
                show_logs
                ;;
            "status")
                show_status
                ;;
            "clean")
                cleanup
                ;;
            *)
                echo "Usage: $0 [build|start|stop|logs|status|clean]"
                exit 1
                ;;
        esac
    else
        # Mode interactif
        while true; do
            show_menu
            handle_choice
            echo
            read -p "Appuyez sur Entrée pour continuer..."
        done
    fi
}

# Gestion des signaux
trap 'log_info "Script interrompu"; exit 1' INT TERM

# Exécution
main "$@"
