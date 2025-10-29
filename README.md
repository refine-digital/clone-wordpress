# Clone WordPress

Infrastructure-aware WordPress site cloner for seamless local development. Clone production WordPress sites from FlyWP-provisioned servers to your local machine with automatic URL updates, database imports, and infrastructure integration.

## Overview

`clone-wordpress.sh` is designed to work with the [clone-infrastructure](https://github.com/refine-digital/clone-infrastructure) project to provide a complete local development workflow for WordPress sites.

## Features

- **Infrastructure-Aware** - Automatically detects and uses existing infrastructure
- **No Hardcoded Credentials** - Reads all credentials from infrastructure `.env`
- **Automatic Naming** - Production `example.com` → Local `local-example.com`
- **URL Replacement** - Automatically updates all WordPress URLs in database
- **Docker-Based** - Uses Docker snapshots for exact production replica
- **Flexible Destination** - Choose where to create site directories
- **Idempotent** - Safe to run multiple times
- **Clean Mode** - Complete removal and re-clone option

## Prerequisites

- macOS or Linux
- Docker and Docker Compose installed
- [clone-infrastructure](https://github.com/refine-digital/clone-infrastructure) set up
- SSH access to production server (configured by clone-infrastructure)
- `rsync` installed
- WordPress CLI (wp-cli) in Docker containers

## Installation

### Quick Install (Recommended)

**1. Install infrastructure tools first:**
```bash
git clone https://github.com/refine-digital/clone-infrastructure.git
cd clone-infrastructure
./install.sh

# Configure PATH if prompted
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Clone your infrastructure
clone-infrastructure dev-fi-01 46.62.207.172
```

**2. Install WordPress cloner:**
```bash
git clone https://github.com/refine-digital/clone-wordpress.git
cd clone-wordpress
./install.sh
```

After installation, the `clone-wordpress` command is available globally.

### Manual Installation (Alternative)

If you prefer to run the script from the project directory:

```bash
# 1. Set up infrastructure first
git clone https://github.com/refine-digital/clone-infrastructure.git
cd clone-infrastructure
./install.sh

# 2. Clone WordPress project
git clone https://github.com/refine-digital/clone-wordpress.git
cd clone-wordpress
chmod +x clone-wordpress.sh
```

Then run with `./clone-wordpress.sh` instead of `clone-wordpress`.

### Updating

To update to the latest version:

```bash
cd clone-wordpress
git pull
./install.sh  # Re-run installer to update command
```

## Usage

### Basic Usage

Clone a WordPress site from production to local:

```bash
clone-wordpress <infrastructure> <domain> [folder] [--clean]
```

### Parameters

- **`infrastructure`** - Infrastructure name (must exist locally)
- **`domain`** - Production WordPress domain
- **`folder`** - (Optional) Destination folder (default: `${HOME}/ProjectFiles/wordpress/`)
- **`--clean`** - (Optional) Remove existing site before cloning

### Examples

**Clone to default location:**
```bash
clone-wordpress dev-fi-01 example.com
# Creates: ~/ProjectFiles/wordpress/local-example-com/
```

**Clone to current directory:**
```bash
clone-wordpress dev-fi-01 example.com .
# Creates: ./local-example-com/
```

**Clone to specific directory:**
```bash
clone-wordpress dev-fi-01 example.com ~/sites
# Creates: ~/sites/local-example-com/
```

**Clean re-clone:**
```bash
clone-wordpress dev-fi-01 example.com --clean
# Removes existing site and clones fresh
```

**Clean re-clone to current directory:**
```bash
clone-wordpress dev-fi-01 example.com . --clean
```

## What It Does

The clone script performs 14 steps:

1. **Extract Database Credentials** - Reads from production wp-config.php
2. **Create Docker Snapshot** - Creates snapshot of production container
3. **Export Database** - Dumps production database
4. **Download Docker Image** - Pulls Docker image with all files
5. **Download Site Files** - Syncs configuration and custom files
6. **Update Local Configuration** - Adjusts LSAPI_CHILDREN for local resources
7. **Load Docker Image** - Imports Docker image to local
8. **Create Local Database** - Creates database in local MySQL
9. **Import Database** - Imports production data
10. **Create docker-compose.yml** - Generates local Docker Compose configuration
11. **Create Site Network** - Sets up Docker networking
12. **Start Container** - Launches WordPress container
13. **Update WordPress URLs** - Replaces production URLs with local URLs
14. **Configure Cloudflared** - Sets up HTTPS access (if cloudflared available)

## Naming Convention

The script automatically applies a consistent naming pattern:

- **Infrastructure**: Same name for production and local
  - Example: `dev-fi-01` (both production and local)

- **Domain**: Automatically prefixed with `local-`
  - Production: `example.com`
  - Local: `local-example.com`

- **Container**: Domain with dashes
  - Production: `example-com`
  - Local: `local-example-com`

- **Directory**: Domain with dashes
  - Production: `example.com/`
  - Local: `local-example-com/`

## Site Structure

After cloning, each site is organized as:

```
{folder}/local-{domain}/
├── docker-compose.yml           # Docker Compose configuration
├── app/
│   ├── wp-config.php           # WordPress configuration
│   ├── wp-cli.yml              # WP-CLI configuration
│   ├── error-pages/            # Custom error pages
│   ├── logs/                   # Application logs
│   └── public/                 # WordPress root
│       ├── wp-admin/
│       ├── wp-content/
│       │   ├── plugins/
│       │   ├── themes/
│       │   └── uploads/
│       └── wp-includes/
├── config/
│   └── ols/
│       └── httpd_config.conf   # OpenLiteSpeed configuration
└── logs/
    └── ols/                    # OpenLiteSpeed logs
```

## Docker Compose Configuration

The generated `docker-compose.yml` includes:

```yaml
version: '3.8'

services:
  openlitespeed:
    image: {domain}:snapshot
    container_name: local-{domain}
    volumes:
      - ./app:/var/www/html
      - ./config/ols:/usr/local/lsws/conf
      - ./logs/ols:/usr/local/lsws/logs
    labels:
      ofelia.enabled: 'true'
      ofelia.job-exec.wpcron: '@every 10m'
    environment:
      - VIRTUAL_HOST=local-{domain}
      - VIRTUAL_PORT=8080
    networks:
      - site-network
      - db-network
      - wordpress-sites

networks:
  site-network:
    name: local-{domain}
    external: true
  wordpress-sites:
    name: wordpress-sites
    external: true
  db-network:
    name: db-network
    external: true
```

## Infrastructure Integration

The script integrates with infrastructure services:

### Required Services

- **nginx-proxy** - Reverse proxy for HTTP access
- **mysql** - Database server
- **redis** - Object caching (optional)
- **wordpress-sites** network - Shared network

### Optional Services

- **cloudflared** - HTTPS access via Cloudflare Tunnel
- **ofelia** - Cron job scheduling

### Configuration Read from Infrastructure

The script reads from `~/.{infrastructure}/.env`:
- `MYSQL_ROOT_PASSWORD` - Database root password
- Other environment variables as needed

### SSH Configuration

Uses SSH config created by clone-infrastructure:
```
Host {infrastructure}-{server-ip}
  HostName {server-ip}
  User fly
  IdentityFile ~/.ssh/id_local{infrastructure}_digops
  IdentitiesOnly yes
```

## URL Replacement

The script automatically updates WordPress URLs:

**Database Search-Replace:**
```bash
# HTTPS to HTTPS
https://example.com → https://local-example.com

# HTTP to HTTPS
http://example.com → https://local-example.com
```

**WordPress Options Updated:**
- `siteurl` - Site URL
- `home` - Home URL
- All URLs in post content, meta data, options

## Accessing Your Site

After cloning, access your site via:

### Via nginx-proxy (HTTP)

Add to `/etc/hosts`:
```
127.0.0.1 local-example.com
```

Then visit: `http://local-example.com`

### Via Cloudflared (HTTPS)

If cloudflared is configured in infrastructure:

1. Update infrastructure cloudflared config:
```yaml
# ~/.{infrastructure}/config/cloudflared/config.yml
ingress:
  - hostname: local-example.com
    service: http://local-example-com:8080
  - service: http_status:404
```

2. Restart cloudflared:
```bash
docker restart cloudflared
```

3. Access: `https://local-example.com`

## Site Management

### Start/Stop/Restart

```bash
cd {folder}/local-{domain}

# Start
docker-compose up -d

# Stop
docker-compose down

# Restart
docker-compose restart

# View logs
docker-compose logs -f
```

### WP-CLI Commands

Execute WordPress CLI commands:

```bash
# General format
docker exec local-{domain} wp {command} --path=/var/www/html/public --allow-root

# Examples
docker exec local-example-com wp plugin list --path=/var/www/html/public --allow-root
docker exec local-example-com wp user list --path=/var/www/html/public --allow-root
docker exec local-example-com wp cache flush --path=/var/www/html/public --allow-root
```

### Database Access

```bash
# Get database name from infrastructure
cd ~/.{infrastructure}
source .env

# Access MySQL
docker exec -it mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD}

# Use database
USE site_12345;

# Query
SELECT option_name, option_value FROM fly_options WHERE option_name IN ('siteurl', 'home');
```

## Idempotency

The script is idempotent - safe to run multiple times:

### Without --clean flag

- Updates existing installation
- Re-imports fresh data from production
- Updates URLs
- Recreates container
- Efficient: only transfers changed files

### With --clean flag

- Completely removes existing installation
- Performs fresh clone
- All 14 steps executed
- Full file transfer

**Example workflow:**
```bash
# Initial clone
clone-wordpress dev-fi-01 example.com

# Update from production (keeps local changes to configs)
clone-wordpress dev-fi-01 example.com

# Fresh start (removes everything)
clone-wordpress dev-fi-01 example.com --clean
```

## Troubleshooting

### Infrastructure Not Found

```
Error: Infrastructure 'dev-fi-01' not found at ~/.dev-fi-01

Please clone the infrastructure first:
  cd ../infrastructure
  ./clone-infrastructure.sh dev-fi-01 <server-ip>
```

**Solution:** Set up infrastructure first using clone-infrastructure project.

### Infrastructure Services Not Running

```
Error: Required infrastructure containers are not running:
  - nginx-proxy
  - mysql
  - redis
```

**Solution:**
```bash
cd ~/.{infrastructure}
docker-compose up -d
```

### Database Import Fails

Check MySQL logs:
```bash
docker logs mysql
```

Verify database credentials:
```bash
cd ~/.{infrastructure}
cat .env
```

### URL Replacement Issues

Manually verify URLs:
```bash
docker exec local-example-com wp option get siteurl --path=/var/www/html/public --allow-root
docker exec local-example-com wp option get home --path=/var/www/html/public --allow-root
```

Manually update if needed:
```bash
docker exec local-example-com wp option update siteurl "https://local-example.com" --path=/var/www/html/public --allow-root
docker exec local-example-com wp option update home "https://local-example.com" --path=/var/www/html/public --allow-root
```

### Container Won't Start

Check logs:
```bash
cd {folder}/local-{domain}
docker-compose logs -f
```

Check for port conflicts:
```bash
docker ps
netstat -an | grep 8080
```

### Site Shows 502 Bad Gateway

1. Verify container is running:
```bash
docker ps | grep local-{domain}
```

2. Check container logs:
```bash
docker logs local-{domain}
```

3. Restart container:
```bash
cd {folder}/local-{domain}
docker-compose restart
```

## Best Practices

1. **Always Set Up Infrastructure First** - Clone infrastructure before WordPress sites
2. **Regular Updates** - Re-run without --clean to sync latest production data
3. **Clean After Major Changes** - Use --clean after major production updates
4. **Backup Local Changes** - Save local modifications before re-cloning
5. **Test Locally** - Verify site works before making production changes
6. **Use Separate Databases** - Each site gets its own database
7. **Monitor Resources** - Docker containers use system resources

## Workflow Example

Complete workflow for local WordPress development:

```bash
# 1. Set up infrastructure (one time)
clone-infrastructure dev-fi-01 46.62.207.172

# 2. Clone WordPress site
clone-wordpress dev-fi-01 example.com

# 3. Add to hosts file
echo "127.0.0.1 local-example.com" | sudo tee -a /etc/hosts

# 4. Access site
open http://local-example.com

# 5. Make local changes, test...

# 6. Update from production (get latest data)
clone-wordpress dev-fi-01 example.com

# 7. Fresh start when needed
clone-wordpress dev-fi-01 example.com --clean
```

## Multiple Sites

You can clone multiple WordPress sites using the same infrastructure:

```bash
# Clone site 1
clone-wordpress dev-fi-01 site1.com

# Clone site 2
clone-wordpress dev-fi-01 site2.com

# Clone site 3
clone-wordpress dev-fi-01 site3.com

# All sites share:
# - nginx-proxy
# - mysql (separate databases)
# - redis
# - cloudflared (if configured)
```

## Version History

- **v1.0.0** - Initial release with infrastructure-aware cloning

## Integration with clone-infrastructure

This project requires [clone-infrastructure](https://github.com/refine-digital/clone-infrastructure) to be set up first.

**Complete Setup:**
1. Install clone-infrastructure
2. Clone production infrastructure
3. Install clone-wordpress
4. Clone WordPress sites

## Performance

**Typical Clone Times:**
- Initial clone: 2-5 minutes (depends on site size)
- Idempotent update: 30-60 seconds (only changed files)
- Clean re-clone: 2-5 minutes (full download)

**Disk Space:**
- Each site: 500MB - 2GB (depends on uploads)
- Docker images: 1-2GB per site
- Database: 10-500MB per site

## Security Notes

- Never commit `.env` files
- Keep SSH keys secure
- Local sites use production credentials - keep secure
- Consider separate local credentials for sensitive data
- Cloudflared provides secure HTTPS without exposing ports

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please open an issue or pull request.

## Support

For issues and questions:
- GitHub Issues: https://github.com/refine-digital/clone-wordpress/issues
- Documentation: https://github.com/refine-digital/clone-wordpress

## Author

Created for infrastructure-centric local WordPress development workflows.

## Related Projects

- [clone-infrastructure](https://github.com/refine-digital/clone-infrastructure) - Infrastructure management toolkit (required)
