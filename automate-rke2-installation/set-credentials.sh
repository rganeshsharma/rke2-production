#!/usr/bin/env bash

set -euo pipefail

# security add-generic-password \
#   -a "$USER" \
#   -s 

export DIGITALOCEAN_TOKEN="$(
    security find-generic-password \
        -a "$USER" \
        -s digitalocean-api-token \
        -w
)"

export SPACES_ACCESS_KEY="$(
    security find-generic-password \
        -a "$USER" \
        -s digitalocean-s3-access-key \
        -w
)"

export SPACES_SECRET_KEY="$(
    security find-generic-password \
        -a "$USER" \
        -s digitalocean-s3-secret-key \
        -w
)"


export GRAFANA_ADMIN_PASSWORD="$(
    security find-generic-password \
        -a "$USER" \
        -s grafana-admin-password \
        -w
)"

export AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY"

echo "DigitalOcean and Spaces credentials loaded."
