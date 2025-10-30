#!/bin/bash

################################################################################
# WordPress Site Cloner (Infrastructure-Aware)
# Clones a production WordPress site to local development environment
#
# Usage: ./clone-wordpress.sh <infrastructure> <domain> [folder] [--clean]
# Example: ./clone-wordpress.sh dev-fi-01 test.refine.digital
#          ./clone-wordpress.sh dev-fi-01 test.refine.digital .
#          ./clone-wordpress.sh dev-fi-01 test.refine.digital ~/sites --clean
#
# Naming Convention:
#   - Infrastructure name stays the same for production and local
#   - Local domain automatically prefixed: local-{domain}
#
# Options:
#   folder     Destination folder (default: ${HOME}/ProjectFiles/wordpress/)
#   --clean    Remove existing site before cloning
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Parse arguments
################################################################################
if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo -e "${RED}Usage: $0 <infrastructure> <domain> [folder] [--clean]${NC}"
    echo ""
    echo "Arguments:"
    echo "  infrastructure   Infrastructure name (e.g., dev-fi-01, refine-digital-app)"
    echo "  domain           Production WordPress domain (e.g., test.refine.digital)"
    echo "  folder           Destination folder (default: \${HOME}/ProjectFiles/wordpress/)"
    echo "                   Use '.' for current directory"
    echo ""
    echo "Naming Convention:"
    echo "  Infrastructure: Same name for production and local (e.g., dev-fi-01)"
    echo "  Local domain: Automatically prefixed with 'local-' (e.g., local-test.refine.digital)"
    echo ""
    echo "Options:"
    echo "  --clean          Remove existing site before cloning"
    echo ""
    echo "Examples:"
    echo "  $0 dev-fi-01 test.refine.digital"
    echo "  $0 dev-fi-01 test.refine.digital ."
    echo "  $0 dev-fi-01 test.refine.digital ~/sites"
    echo "  $0 dev-fi-01 test.refine.digital . --clean"
    echo ""
    exit 1
fi

INFRASTRUCTURE=$1
DOMAIN=$2
CLEAN_MODE=false
LOCAL_BASE_DIR="${HOME}/ProjectFiles/wordpress"

# Parse optional folder and --clean arguments
if [ $# -ge 3 ]; then
    if [ "$3" == "--clean" ]; then
        CLEAN_MODE=true
    else
        # Third argument is folder
        if [ "$3" == "." ]; then
            LOCAL_BASE_DIR="$(pwd)"
        else
            LOCAL_BASE_DIR="$3"
        fi

        # Check for --clean as fourth argument
        if [ $# -eq 4 ] && [ "$4" == "--clean" ]; then
            CLEAN_MODE=true
        fi
    fi
fi

# Convert to absolute path and ensure directory exists
LOCAL_BASE_DIR=$(cd "$LOCAL_BASE_DIR" 2>/dev/null && pwd || (mkdir -p "$LOCAL_BASE_DIR" && cd "$LOCAL_BASE_DIR" && pwd))

# Automatically generate local domain using naming convention
LOCAL_DOMAIN="local-${DOMAIN}"

# Configuration from infrastructure
INFRA_DIR="${HOME}/.${INFRASTRUCTURE}"
PRODUCTION_USER="fly"

# Domain processing
DOMAIN_NODOTS="${DOMAIN//./}"
PROD_CONTAINER="${DOMAIN_NODOTS}-openlitespeed-1"
LOCAL_CONTAINER="${LOCAL_DOMAIN//./-}"
SITE_DIR="${DOMAIN}"  # Production directory (with dots)
LOCAL_SITE_DIR="${LOCAL_DOMAIN//./-}"  # Local directory (with dashes)
IMAGE_NAME="${DOMAIN//./-}"  # Docker image name

# Setup logging
LOG_FILE="${LOCAL_BASE_DIR}/clone-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo -e "${GREEN}=== WordPress Site Cloner ===${NC}"
echo "Infrastructure: ${INFRASTRUCTURE}"
echo "Production Site: https://${DOMAIN}"
echo "Local Site: https://${LOCAL_DOMAIN}"
echo "Destination: ${LOCAL_BASE_DIR}"
echo "Clean mode: ${CLEAN_MODE}"
echo "Log file: ${LOG_FILE}"
echo ""

################################################################################
# Infrastructure Verification
################################################################################
echo -e "${YELLOW}Verifying infrastructure...${NC}"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    echo ""
    echo "Please start Docker Desktop and try again."
    echo ""
    exit 1
fi
echo "  ✓ Docker is running"

# Check if infrastructure directory exists
if [ ! -d "${INFRA_DIR}" ]; then
    echo -e "${RED}Error: Infrastructure '${INFRASTRUCTURE}' not found at ${INFRA_DIR}${NC}"
    echo ""
    echo "Please clone the infrastructure first:"
    echo "  cd ../infrastructure"
    echo "  ./clone-infrastructure.sh ${INFRASTRUCTURE} <server-ip>"
    echo ""
    exit 1
fi

# Read infrastructure configuration
if [ ! -f "${INFRA_DIR}/.env" ]; then
    echo -e "${RED}Error: Infrastructure .env file not found${NC}"
    exit 1
fi

# Source infrastructure environment
source "${INFRA_DIR}/.env"

# Verify required environment variables
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo -e "${RED}Error: MYSQL_ROOT_PASSWORD not found in infrastructure .env${NC}"
    exit 1
fi

echo "  ✓ Infrastructure directory found"
echo "  ✓ Configuration loaded from infrastructure"

# Check if infrastructure services are running
REQUIRED_CONTAINERS=("nginx-proxy" "mysql" "redis")
MISSING_CONTAINERS=()

for container in "${REQUIRED_CONTAINERS[@]}"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        MISSING_CONTAINERS+=("$container")
    fi
done

if [ ${#MISSING_CONTAINERS[@]} -gt 0 ]; then
    echo -e "${RED}Error: Required infrastructure containers are not running:${NC}"
    for container in "${MISSING_CONTAINERS[@]}"; do
        echo -e "${RED}  - ${container}${NC}"
    done
    echo ""
    echo -e "${YELLOW}Please start the infrastructure:${NC}"
    echo "  cd ${INFRA_DIR}"
    echo "  docker-compose up -d"
    echo ""
    exit 1
fi

# Verify networks exist
REQUIRED_NETWORKS=("wordpress-sites" "db-network")
MISSING_NETWORKS=()

for network in "${REQUIRED_NETWORKS[@]}"; do
    if ! docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
        MISSING_NETWORKS+=("$network")
    fi
done

if [ ${#MISSING_NETWORKS[@]} -gt 0 ]; then
    echo -e "${RED}Error: Required Docker networks do not exist:${NC}"
    for network in "${MISSING_NETWORKS[@]}"; do
        echo -e "${RED}  - ${network}${NC}"
    done
    echo ""
    echo "These should have been created by the infrastructure."
    echo "Try restarting the infrastructure:"
    echo "  cd ${INFRA_DIR}"
    echo "  docker-compose down && docker-compose up -d"
    exit 1
fi

echo -e "${GREEN}✓ Infrastructure verified${NC}"
echo "  - nginx-proxy: running"
echo "  - mysql: running"
echo "  - redis: running"
echo "  - wordpress-sites network: exists"
echo "  - db-network: exists"
echo ""

################################################################################
# Get SSH configuration from infrastructure
################################################################################
echo -e "${YELLOW}Getting SSH configuration...${NC}"

# Find SSH host from infrastructure SSH config
SSH_HOST=$(grep -A 3 "Host.*${INFRASTRUCTURE}" ~/.ssh/config 2>/dev/null | grep "HostName" | awk '{print $2}' | head -1)

if [ -z "$SSH_HOST" ]; then
    echo -e "${RED}Error: Could not find SSH host for infrastructure '${INFRASTRUCTURE}'${NC}"
    echo ""
    echo "Please check your ~/.ssh/config file."
    echo "It should contain an entry created by clone-infrastructure.sh"
    exit 1
fi

# Use the SSH config entry directly
SSH_CONFIG_HOST=$(grep "Host.*${INFRASTRUCTURE}" ~/.ssh/config | awk '{print $2}' | head -1)

echo "  ✓ SSH host: ${PRODUCTION_USER}@${SSH_HOST}"
echo "  ✓ SSH config: ${SSH_CONFIG_HOST}"
echo ""

################################################################################
# Step 0: Clean up existing installation if --clean flag is set
################################################################################
if [ "$CLEAN_MODE" == "true" ]; then
    echo -e "${BLUE}[0/14] Cleaning up existing installation...${NC}"

    # Stop and remove container
    cd "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}" 2>/dev/null || true
    docker-compose -f docker-compose.yml down 2>/dev/null || true
    docker stop ${LOCAL_CONTAINER} 2>/dev/null || true
    docker rm ${LOCAL_CONTAINER} 2>/dev/null || true
    echo "  Removed container"

    # Remove Docker image
    docker rmi ${IMAGE_NAME}:snapshot 2>/dev/null || true
    echo "  Removed Docker image"

    # Remove network
    docker network rm ${LOCAL_DOMAIN} 2>/dev/null || true
    echo "  Removed network"

    # Remove site directory
    rm -rf "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}" 2>/dev/null || true
    echo "  Removed site directory"

    # Remove temporary files
    rm -f "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-db.sql" 2>/dev/null || true
    rm -f "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-image.tar" 2>/dev/null || true
    echo "  Removed temporary files"

    # Note: Cloudflared config now managed by infrastructure, no cleanup needed here

    echo -e "${GREEN}  Cleanup complete${NC}"
    echo ""
fi

################################################################################
# Step 1: Extract database credentials from production
################################################################################
echo -e "${YELLOW}[1/14] Extracting database credentials...${NC}"

DB_CREDS=$(ssh ${PRODUCTION_USER}@${SSH_CONFIG_HOST} "cat ~/${SITE_DIR}/app/wp-config.php | grep \"DB_\"")
DB_NAME=$(echo "$DB_CREDS" | grep "DB_NAME" | cut -d "'" -f 4)
DB_USER=$(echo "$DB_CREDS" | grep "DB_USER" | cut -d "'" -f 4)
DB_PASS=$(echo "$DB_CREDS" | grep "DB_PASSWORD" | cut -d "'" -f 4)
DB_CHARSET=$(echo "$DB_CREDS" | grep "DB_CHARSET" | cut -d "'" -f 4)

echo "  Database: ${DB_NAME}"
echo "  User: ${DB_USER}"

################################################################################
# Step 2: Create Docker snapshot on production
################################################################################
echo -e "${YELLOW}[2/14] Creating Docker snapshot...${NC}"

ssh ${PRODUCTION_USER}@${SSH_CONFIG_HOST} "docker commit ${PROD_CONTAINER} ${IMAGE_NAME}:snapshot"

################################################################################
# Step 3: Export database from production
################################################################################
echo -e "${YELLOW}[3/14] Exporting database...${NC}"

ssh ${PRODUCTION_USER}@${SSH_CONFIG_HOST} \
    "docker exec mysql mysqldump -u ${DB_USER} -p${DB_PASS} --no-tablespaces ${DB_NAME}" \
    > "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-db.sql"

echo "  Exported $(wc -l < "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-db.sql") lines"

################################################################################
# Step 4: Stream Docker image to local
################################################################################
echo -e "${YELLOW}[4/14] Downloading Docker image...${NC}"

ssh ${PRODUCTION_USER}@${SSH_CONFIG_HOST} "docker save ${IMAGE_NAME}:snapshot" \
    > "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-image.tar"

IMAGE_SIZE=$(du -h "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-image.tar" | cut -f1)
echo "  Downloaded ${IMAGE_SIZE}"

################################################################################
# Step 5: Download site files
################################################################################
echo -e "${YELLOW}[5/14] Downloading site files...${NC}"

# Use rsync to efficiently sync only changed files
rsync -avz --delete \
    ${PRODUCTION_USER}@${SSH_CONFIG_HOST}:~/${SITE_DIR}/ \
    "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}/"

echo "  Synced site files"

################################################################################
# Step 6: Update local configuration
################################################################################
echo -e "${YELLOW}[6/14] Updating local configuration...${NC}"

# Update LSAPI_CHILDREN in httpd_config.conf
sed -i '' 's/PHP_LSAPI_CHILDREN=10/PHP_LSAPI_CHILDREN=35/g' \
    "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}/config/ols/httpd_config.conf"

echo "  Updated LSAPI_CHILDREN to 35"

################################################################################
# Step 7: Load Docker image
################################################################################
echo -e "${YELLOW}[7/14] Loading Docker image...${NC}"

docker load -i "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-image.tar"

echo "  Loaded image: ${IMAGE_NAME}:snapshot"

################################################################################
# Step 8: Create database
################################################################################
echo -e "${YELLOW}[8/14] Creating local database...${NC}"

# Get collation from dump file
DB_COLLATION=$(grep -m1 "DEFAULT CHARSET" "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-db.sql" | \
    sed -n 's/.*COLLATE=\([^ ;]*\).*/\1/p')

if [ -z "$DB_COLLATION" ]; then
    DB_COLLATION="utf8mb4_unicode_520_ci"
fi

echo "  Collation: ${DB_COLLATION}"

# Drop existing database if it exists
docker exec mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} \
    -e "DROP DATABASE IF EXISTS ${DB_NAME}; DROP USER IF EXISTS '${DB_USER}'@'%'; FLUSH PRIVILEGES;" \
    2>/dev/null || true

# Create database
docker exec mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} \
    -e "CREATE DATABASE ${DB_NAME} CHARACTER SET ${DB_CHARSET} COLLATE ${DB_COLLATION};"

# Create user
docker exec mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} \
    -e "CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}'; \
        GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%'; \
        FLUSH PRIVILEGES;"

################################################################################
# Step 9: Import database
################################################################################
echo -e "${YELLOW}[9/14] Importing database...${NC}"

docker exec -i mysql mysql -u ${DB_USER} -p${DB_PASS} ${DB_NAME} \
    < "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-db.sql"

echo "  Database imported"

################################################################################
# Step 10: Create local docker-compose.yml
################################################################################
echo -e "${YELLOW}[10/14] Creating local docker-compose.yml...${NC}"

cat > "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}/docker-compose.yml" << COMPOSE_EOF
services:
  openlitespeed:
    image: ${IMAGE_NAME}:snapshot
    pull_policy: never
    container_name: ${LOCAL_CONTAINER}
    restart: unless-stopped
    volumes:
      - './app:/var/www/html'
      - './logs/ols:/usr/local/lsws/logs'
      - './config/php/ols.ini:/usr/local/lsws/lsphp82/etc/php/8.2/mods-available/ols.ini'
      - './config/ols/httpd_config.conf:/usr/local/lsws/conf/httpd_config.conf'
      - './config/ols/vhconf.conf:/usr/local/lsws/conf/vhosts/flywp/vhconf.conf'
    labels:
      ofelia.enabled: 'true'
      ofelia.job-exec.wpcron-${LOCAL_CONTAINER}.schedule: '@every 10m'
      ofelia.job-exec.wpcron-${LOCAL_CONTAINER}.user: www-data
      ofelia.job-exec.wpcron-${LOCAL_CONTAINER}.command: 'wp cron event run --due-now --path=/var/www/html/public'
    environment:
      - VIRTUAL_HOST=${LOCAL_DOMAIN}
      - VIRTUAL_PORT=8080
    networks:
      - site-network
      - db-network
      - wordpress-sites

networks:
  site-network:
    name: ${LOCAL_DOMAIN}
    external: true
  wordpress-sites:
    name: wordpress-sites
    external: true
  db-network:
    name: db-network
    external: true
COMPOSE_EOF

echo "  Created docker-compose.yml"

################################################################################
# Step 11: Create site network
################################################################################
echo -e "${YELLOW}[11/14] Creating site network...${NC}"

docker network create ${LOCAL_DOMAIN} 2>/dev/null || echo "  Network already exists"

################################################################################
# Step 12: Start container with docker-compose
################################################################################
echo -e "${YELLOW}[12/14] Starting container with docker-compose...${NC}"

cd "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}"
docker-compose down 2>/dev/null || true

# Force remove any existing container with same name
docker stop ${LOCAL_CONTAINER} 2>/dev/null || true
docker rm ${LOCAL_CONTAINER} 2>/dev/null || true

docker-compose up -d

echo "  Container started: ${LOCAL_CONTAINER}"

# Wait for container to be ready
sleep 5

################################################################################
# Step 13: Update WordPress URLs
################################################################################
echo -e "${YELLOW}[13/14] Updating WordPress URLs...${NC}"

# Disable object cache first (to avoid Redis dependency issues)
docker exec ${LOCAL_CONTAINER} wp option update litespeed.conf.object 0 \
    --path=/var/www/html/public --allow-root 2>/dev/null || true

# Update URLs
docker exec ${LOCAL_CONTAINER} wp search-replace "https://${DOMAIN}" "https://${LOCAL_DOMAIN}" \
    --path=/var/www/html/public --allow-root --precise

docker exec ${LOCAL_CONTAINER} wp search-replace "http://${DOMAIN}" "https://${LOCAL_DOMAIN}" \
    --path=/var/www/html/public --allow-root --precise

# Flush cache
docker exec ${LOCAL_CONTAINER} wp cache flush \
    --path=/var/www/html/public --allow-root 2>/dev/null || true

SITE_URL=$(docker exec ${LOCAL_CONTAINER} wp option get siteurl --path=/var/www/html/public --allow-root)
echo "  Site URL: ${SITE_URL}"

################################################################################
# Step 14: Configure Cloudflared (if available in infrastructure)
################################################################################
echo -e "${YELLOW}[14/14] Configuring Cloudflared access...${NC}"

# Check if cloudflared is running in infrastructure
if docker ps --format '{{.Names}}' | grep -q "cloudflared"; then
    echo "  ✓ Cloudflared is running in infrastructure"
    echo "  Note: To add ${LOCAL_DOMAIN} to the tunnel, update:"
    echo "       ${INFRA_DIR}/config/cloudflared/config.yml"
    echo "  Then restart: docker restart cloudflared"
else
    echo "  ⚠️  Cloudflared not found in infrastructure"
    echo "  Site will be accessible via nginx-proxy on localhost"
    echo "  For HTTPS access, configure cloudflared in infrastructure"
fi

################################################################################
# Cleanup temporary files
################################################################################
echo -e "${BLUE}Cleaning up temporary files...${NC}"

# Remove database dump
if [ -f "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-db.sql" ]; then
    rm -f "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-db.sql"
    echo "  Removed database dump"
fi

# Remove Docker image tar
if [ -f "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-image.tar" ]; then
    rm -f "${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}-image.tar"
    echo "  Removed Docker image tar"
fi

# Remove production snapshot from production server
ssh ${PRODUCTION_USER}@${SSH_CONFIG_HOST} "docker rmi ${IMAGE_NAME}:snapshot" 2>/dev/null || true
echo "  Removed production snapshot"

echo ""
echo -e "${GREEN}=== Clone Complete! ===${NC}"
echo ""
echo "Infrastructure: ${INFRASTRUCTURE}"
echo "Production: https://${DOMAIN}"
echo "Local: https://${LOCAL_DOMAIN}"
echo ""
echo "Site location: ${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}"
echo "Container: ${LOCAL_CONTAINER}"
echo "Database: ${DB_NAME}"
echo ""
echo "Manage the site:"
echo "  cd ${LOCAL_BASE_DIR}/${LOCAL_SITE_DIR}"
echo "  docker-compose up -d      # Start"
echo "  docker-compose down       # Stop"
echo "  docker-compose logs -f    # View logs"
echo ""
echo "To re-clone this site:"
echo "  ./clone-wordpress.sh ${INFRASTRUCTURE} ${DOMAIN} --clean"
echo ""
echo "Log file: ${LOG_FILE}"
echo ""
if docker ps --format '{{.Names}}' | grep -q "cloudflared"; then
    echo -e "${GREEN}Cloudflared is running - configure ${LOCAL_DOMAIN} in infrastructure for HTTPS access${NC}"
else
    echo -e "${YELLOW}Note: Cloudflared not running. Site accessible via http://localhost${NC}"
fi
echo ""
