#!/bin/bash

# Define variables
CONTAINER_NAME="portainer"
CERTS_PATH="/mnt/vgdata-data/Applications/Portainer"
IMAGE="portainer/portainer-ce:lts"
DATA_VOLUME="portainer_data"

echo "⚠️  WARNING: This will stop and replace your current Portainer container."
echo "👉 Before continuing, please go to Portainer UI > Settings > Backup and download a backup of your data."
read -rp "📥 Have you downloaded a backup? Type 'yes' to continue: " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "❌ Operation cancelled."
  exit 1
fi

echo "🛑 Stopping container: $CONTAINER_NAME"
docker stop "$CONTAINER_NAME"

echo "🗑 Removing container: $CONTAINER_NAME"
docker rm "$CONTAINER_NAME"

echo "⬇️ Pulling latest image: $IMAGE"
docker pull "$IMAGE"

echo "🚀 Starting new container..."
docker run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  --name="$CONTAINER_NAME" \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$DATA_VOLUME":/data \
  -v "$CERTS_PATH":/certs \
  "$IMAGE" \
  --sslcert /certs/portainer.crt \
  --sslkey /certs/portainer.key

echo "✅ Portainer has been updated and is now running on https://localhost:9443"

