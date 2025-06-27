# RustDesk Web Client - Version Optimisée

Cette version optimisée du client web RustDesk résout les problèmes de build avec Flutter 3.24+ en utilisant Flutter 3.22.1 et intègre les améliorations du fork MonsieurBiche.

## 🚀 Fonctionnalités

- ✅ **Flutter 3.22.1** - Version stable compatible (tag: fix-build)
- ✅ **Configuration flexible** - Choix entre différentes branches et repositories
- ✅ **Support WSS** - Configuration optionnelle pour connexions sécurisées
- ✅ **Build optimisé** - Cache et dépendances améliorés
- ✅ **Serveur Nginx** - Performance et stabilité
- ✅ **Support WebSocket** - Configuration WSS prête
- ✅ **Docker multi-stage** - Image optimisée
- ✅ **Health checks** - Monitoring intégré
- ✅ **Fallback automatique** - Fork MonsieurBiche → Officiel

## 📋 Prérequis

- Docker 20.10+
- Docker Compose 2.0+
- 4GB RAM minimum pour le build
- Connexion internet stable

## ⚙️ Configuration Flexible

### Choix de la branche

Ce build supporte plusieurs tags du fork MonsieurBiche :

| Tag | Description | Usage |
|---------|-------------|-------|
| `fix-build` | Corrections de build uniquement | Développement stable |
| `enable-wss` | Support WSS pour HTTPS | **Production recommandée** |
| `add-features` | Fonctionnalités avancées | Expérimental |

### Variables d'environnement

```bash
# Tag à utiliser
export RUSTDESK_TAG=enable-wss

# Repository source
export RUSTDESK_REPO=MonsieurBiche/rustdesk-web-client

# Support WSS
export ENABLE_WSS=true
```

Voir `config-examples.env` pour plus d'exemples.

## 🚀 Installation et Build

### Option 1: Docker Compose (Recommandé)

```bash
# Cloner ou utiliser le répertoire existant
cd /home/pmietlicki/rustdesk

# Build et démarrage
docker-compose up --build -d

# Vérifier les logs
docker-compose logs -f rustdesk-web

# Accéder à l'application
open http://localhost:5000
```

### Option 1b: Script de build automatisé

```bash
# Build avec configuration par défaut (fix-build)
./build.sh build

# Build avec support WSS (recommandé pour production)
export RUSTDESK_TAG=enable-wss && export ENABLE_WSS=true && ./build.sh build

# Build avec toutes les fonctionnalités
export RUSTDESK_TAG=add-features && ./build.sh build

# Build avec nettoyage
./build.sh clean build

# Arrêt des services
./build.sh stop
```

### Option 2: Docker manuel

```bash
# Build de l'image
docker build -t rustdesk-web-client .

# Démarrage du conteneur
docker run -d \
  --name rustdesk-web \
  -p 5000:80 \
  -p 21117:21117 \
  rustdesk-web-client

# Vérifier les logs
docker logs -f rustdesk-web
```

## 🔧 Configuration

### Variables d'environnement

```bash
# Ports
RUSTDESK_WEB_PORT=5000      # Port du serveur web
RUSTDESK_WS_PORT=21117      # Port WebSocket

# Build (dans docker-compose.yml)
FLUTTER_VERSION=3.22.1      # Version Flutter
RUSTDESK_TAG=fix-build      # Tag RustDesk
```

### Personnalisation des ports

```yaml
# Dans docker-compose.yml
ports:
  - "8080:5000"  # Web sur port 8080
  - "8117:21117" # WebSocket sur port 8117
```

## 🌐 Configuration Production (SSL/WSS)

Pour un déploiement en production avec HTTPS/WSS :

1. **Créer les certificats SSL**
```bash
mkdir ssl
# Copier cert.pem et key.pem dans ./ssl/
```

2. **Décommenter la section SSL** dans `docker-compose.yml`

3. **Configurer le reverse proxy** (Nginx/Traefik)

## 📊 Monitoring et Debugging

### Health Check
```bash
# Vérifier la santé du conteneur
docker ps
# Status: healthy/unhealthy

# Test manuel
curl -f http://localhost:5000/
```

### Logs détaillés
```bash
# Logs du build
docker-compose logs rustdesk-web

# Logs en temps réel
docker-compose logs -f --tail=100 rustdesk-web

# Logs Nginx spécifiques
docker exec rustdesk-web-client tail -f /var/log/nginx/access.log
```

### Debug du conteneur
```bash
# Accès shell
docker exec -it rustdesk-web-client bash

# Vérifier les assets
ls -la /app/web/

# Tester Nginx
nginx -t
```

## 🔍 Résolution des problèmes

### Build échoue
```bash
# Nettoyer et rebuilder
docker-compose down
docker system prune -f
docker-compose up --build --no-cache
```

### Page blanche
```bash
# Vérifier les assets
docker exec rustdesk-web-client ls -la /app/web/

# Vérifier index.html
docker exec rustdesk-web-client cat /app/web/index.html | head
```

### WebSocket ne fonctionne pas
```bash
# Vérifier la configuration Nginx
docker exec rustdesk-web-client nginx -T | grep -A 10 "location /ws"

# Tester la connectivité
telnet localhost 21117
```

## 📈 Optimisations

### Build plus rapide
```bash
# Utiliser le cache Docker
export DOCKER_BUILDKIT=1
docker-compose build --parallel
```

### Réduire la taille de l'image
- L'image utilise déjà un build multi-stage
- Assets optimisés avec tree-shaking
- Dépendances minimales en runtime

## 🆚 Différences avec l'original

| Fonctionnalité | Original | Cette version |
|---|---|---|
| Flutter | 3.24.3 ❌ | 3.22.1 ✅ |
| Serveur | Python http.server | Nginx ✅ |
| WebSocket | Non configuré | Prêt ✅ |
| Health checks | Non | Oui ✅ |
| Cache build | Basique | Optimisé ✅ |
| Fallback | Non | MonsieurBiche ✅ |

## 📚 Ressources

- [RustDesk Official](https://github.com/rustdesk/rustdesk)
- [MonsieurBiche Fork](https://github.com/MonsieurBiche/rustdesk-web-client)
- [Flutter 3.22.1 Docs](https://docs.flutter.dev/)
- [RustDesk Web V2](https://rustdesk.com/web)

## 🤝 Contribution

Les améliorations sont les bienvenues ! Ce Dockerfile résout les problèmes de compatibilité Flutter 3.24+ identifiés dans la communauté RustDesk.

## 📄 Licence

Suit la licence du projet RustDesk original (AGPL-3.0).
