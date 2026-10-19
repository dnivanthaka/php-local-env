#!/bin/bash

# Exit on error
set -e

# Project paths
BACKEND_DIR="../backend"
FRONTEND_DIR="../frontend"

# Visual helpers
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

# Helper function to enforce safe host-level file permissions
apply_permissions() {
    info "Syncing local user ownership & applying dev file permissions..."
    sudo chown -R $USER:$USER "$BACKEND_DIR"
    chmod -R 775 "$BACKEND_DIR"
    
    # Check if container is up before applying internal write modes
    if [ "$(docker compose ps -q app)" ]; then
        docker compose exec -T app chmod -R 777 storage bootstrap/cache
    fi
}

case "$1" in
    start)
        info "Spinning up infrastructure containers..."
        docker compose up -d
        apply_permissions
        success "Ecosystem is running at http://localhost:8080"
        ;;

    install)
        info "Installing core Laravel vendor packages inside the container..."
        docker compose exec -T app composer install
        
        info "Injecting Quality Suite (Pest, PHPStan, Rector, Pint)..."
        docker compose exec -T app composer require pestphp/pest pestphp/pest-plugin-laravel --dev --with-all-dependencies --no-interaction
        docker compose exec -T app composer require phpstan/phpstan rector/rector laravel/pint --dev --no-interaction
        
        # Initialize tool configuration files if they are missing
        if [ ! -f "$BACKEND_DIR/rector.php" ]; then
            info "Writing standardized rector.php configuration..."
cat << 'EOF' > "$BACKEND_DIR/rector.php"
<?php declare(strict_types=1);

use Rector\Config\RectorConfig;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromAssignsRector;

return RectorConfig::configure()
    ->withPaths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/routes',
    ])
    ->withPhpSets(php84: true)
    ->withRules([
        TypedPropertyFromAssignsRector::class,
    ]);
EOF
            apply_permissions
        fi

        if [ ! -d "$BACKEND_DIR/tests/Pest.php" ] && [ ! -f "$BACKEND_DIR/tests/Pest.php" ]; then
            info "Initialising Pest profile layers..."
            docker compose exec -T app ./vendor/bin/pest --init || true
        fi
        
        apply_permissions
        success "All frameworks, testing frameworks, and tooling setups successfully installed!"
        ;;

    build)
        info "Executing a clean full-stack compilation build..."
        docker compose up -d --build
        apply_permissions
        
        # Auto-run install steps if the Pest testing binary doesn't exist yet [1]
        if [ ! -f "$BACKEND_DIR/vendor/bin/pest" ]; then
            info "Detecting missing or broken testing binaries. Automating tool installations..."
            "$0" install
        fi
        
        info "Waiting for MySQL to boot and accept connections..."
        until docker compose exec -T mysql mysqladmin ping -h"127.0.0.1" --silent; do
            echo -n "."
            sleep 1
        done
        echo ""
        
        info "Running post-boot core application initialisations..."
        if [ ! -f "$BACKEND_DIR/.env" ] && [ -f "$BACKEND_DIR/.env.example" ]; then
            cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env"
            info "Created initial backend .env layout from template."
        fi
        
        docker compose exec -T app php artisan key:generate --ansi || true
        docker compose exec -T app php artisan config:clear --ansi
        docker compose exec -T app php artisan migrate --ansi
        success "Build configuration compiled, dependencies configured, and databases synced!"
        ;;

    stop)
        info "Stopping environment..."
        docker compose down
        success "Containers stopped successfully."
        ;;

    clean)
        info "PERMANENT DESTRUCTION: Tearing down containers, caches and volumes..."
        docker compose down -v
        success "Environment completely wiped."
        ;;

    migrate)
        info "Running database schemas migration execution thread..."
        docker compose exec -T app php artisan migrate
        ;;

    pest|test)
        info "Executing Pest testing framework suite..."
        docker compose exec -T app ./vendor/bin/pest "${@:2}"
        ;;

    pint|lint)
        info "Executing Laravel Pint styling linter auto-fixer..."
        docker compose exec -T app ./vendor/bin/pint "${@:2}"
        ;;

    phpstan|analyse)
        info "Executing PHPStan Level 5 static program analysis checks..."
        docker compose exec -T app ./vendor/bin/phpstan analyse app
        ;;

    rector)
        info "Executing Rector source code rule structural refactoring dry run..."
        docker compose exec -T app ./vendor/bin/rector process --dry-run
        ;;

    shell|ssh)
        info "Opening an interactive bash terminal inside the PHP 8.5 app container..."
        docker compose exec app bash
        ;;

    *)
        echo "Usage: ./run.sh {start|stop|build|install|clean|migrate|test|lint|analyse|rector}"
        echo "------------------------------------------------------------------"
        echo "  start     : Resumes running background container layers"
        echo "  build     : Re-compiles Dockerfiles, verifies libraries & runs migrations"
        echo "  install   : Manually installs/restores Pest, static tooling and vendors"
        echo "  stop      : Halts active background container components gracefully"
        echo "  test      : Runs your Pest testing suites"
        echo "  lint      : Formats backend code using Laravel Pint"
        echo "------------------------------------------------------------------"
        exit 1
        ;;
esac
