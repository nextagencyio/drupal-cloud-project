# Automated Docker Build Pipeline

This repository automatically triggers Docker image builds in the decoupled-docker repo when code changes are pushed to main.

## How It Works
1. Push code to nextagencyio/decoupled-project
2. GitHub Actions triggers decoupled-docker image rebuild
3. Self-hosted runner builds and pushes new image to Docker Hub
4. New sites automatically use the latest image
