#!/usr/bin/env bash

# ==============================================================================
# DeMoD Game Server Network - Production Deployment Script
#
# Usage:
#   ./deploy.sh [options]
#
# Options:
#   -p, --push      Push images to Docker Hub after building
#   -r, --registry  Specify registry namespace (default: alh477)
#   -h, --help      Show this help message
#
# Copyright (c) 2025 DeMoD LLC. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of DeMoD LLC nor the names of its contributors may be
#    used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
# ==============================================================================

set -euo pipefail

# Configuration
REGISTRY_NAMESPACE="alh477"
PUSH_IMAGES=false
SERVICES=("dcf-id" "gsn-selector" "gsn-meter" "gsn-discord-bot")
REQUIRED_NETWORKS=("frontend")
REQUIRED_VOLUMES=("demod-data")

# Formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

log_info() { echo -e "${GREEN}[INFO]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $1"; }

print_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo "Options:"
    echo "  -p, --push      Push images to Docker Hub after building"
    echo "  -r, --registry  Specify registry namespace (default: alh477)"
    echo "  -h, --help      Show this help message"
}

check_dependencies() {
    log_info "Checking dependencies..."
    local deps=("docker" "nix" "jq")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Missing required dependency: $cmd"
            exit 1
        fi
    done
}

setup_infrastructure() {
    log_info "Verifying Docker infrastructure..."

    # Create Networks
    for net in "${REQUIRED_NETWORKS[@]}"; do
        if docker network inspect "$net" >/dev/null 2>&1; then
            log_info "Network '$net' already exists."
        else
            log_info "Creating network '$net'..."
            docker network create "$net"
        fi
    done

    # Create Volumes
    for vol in "${REQUIRED_VOLUMES[@]}"; do
        if docker volume inspect "$vol" >/dev/null 2>&1; then
            log_info "Volume '$vol' already exists."
        else
            log_info "Creating volume '$vol'..."
            docker volume create "$vol"
        fi
    done
}

build_and_load() {
    log_info "Starting Nix builds..."

    for service in "${SERVICES[@]}"; do
        local nix_target=".#docker-${service}"
        local local_tag="demod/${service}:latest"
        local remote_tag="${REGISTRY_NAMESPACE}/${service}:latest"

        echo "----------------------------------------------------------------"
        log_info "Processing service: $service"
        
        # Build using Nix
        if nix build "$nix_target" --out-link "result-${service}"; then
            log_info "Build successful. Loading into Docker..."
            
            # Load image
            if ./result-${service} | docker load; then
                log_info "Image loaded: $local_tag"
                
                # Retag for user registry
                docker tag "$local_tag" "$remote_tag"
                log_info "Tagged as: $remote_tag"

                # Optional Push
                if [ "$PUSH_IMAGES" = true ]; then
                    log_info "Pushing $remote_tag to Docker Hub..."
                    docker push "$remote_tag"
                fi
            else
                log_error "Failed to load Docker image for $service"
                exit 1
            fi
        else
            log_error "Nix build failed for $service"
            exit 1
        fi
    done
    
    # Clean up symlinks
    rm -f result-*
}

verify_env() {
    if [ ! -f .env ]; then
        log_warn "No .env file found. Creating from template..."
        cat <<EOF > .env
# Service Secrets
DCF_ID_INTERNAL_KEY=changeme
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Discord Integration
DISCORD_CLIENT_ID=...
DISCORD_CLIENT_SECRET=...
DISCORD_TOKEN=...
BOT_PREFIX=!gs
ALLOWED_ROLES=Admin,Moderator

# Configuration
DCF_PUBLIC_URL=https://dcf.demod.ltd
LOG_LEVEL=info
MIN_BALANCE_TO_START=5.00
EOF
        log_warn "Created .env template. Please edit it before starting the stack."
        exit 1
    fi
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--push)
                PUSH_IMAGES=true
                shift
                ;;
            -r|--registry)
                REGISTRY_NAMESPACE="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    check_dependencies
    verify_env
    setup_infrastructure
    build_and_load

    log_info "Deployment preparation complete."
    log_info "To start the stack run: docker compose up -d"
}

main "$@"
