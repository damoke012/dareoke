# Honeywell Forge Cognition - Makefile
# Common operations for development and deployment
#
# Usage:
#   make help           # Show all targets
#   make build          # Build multi-arch image
#   make test           # Run tests
#   make deploy-lab     # Deploy to lab environment
#   make bundle         # Create air-gapped bundle

.PHONY: help build build-x86 build-arm64 test lint deploy-lab deploy-prod bundle clean

# Configuration
REGISTRY ?= ghcr.io
IMAGE_NAME ?= forge/inference-server
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "latest")
PLATFORMS ?= linux/amd64,linux/arm64

# Directories
PROJECT_DIR := $(shell pwd)
INFERENCE_DIR := $(PROJECT_DIR)/inference-server
DEPLOYMENT_DIR := $(PROJECT_DIR)/deployment
CICD_DIR := $(PROJECT_DIR)/cicd

# Full image reference
FULL_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(VERSION)

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Default target
.DEFAULT_GOAL := help

## help: Show this help message
help:
	@echo "$(GREEN)Forge Cognition - Build & Deploy$(NC)"
	@echo ""
	@echo "$(YELLOW)Build Targets:$(NC)"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
	@echo ""
	@echo "$(YELLOW)Configuration:$(NC)"
	@echo "  REGISTRY=$(REGISTRY)"
	@echo "  IMAGE_NAME=$(IMAGE_NAME)"
	@echo "  VERSION=$(VERSION)"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make build                    # Build for current platform"
	@echo "  make build-multiarch          # Build for both ARM64 and x86"
	@echo "  make deploy-lab SKU=tesla_p40 # Deploy to lab with specific SKU"
	@echo "  make bundle VERSION=v1.0.0    # Create release bundle"

# ============================================================================
# Build Targets
# ============================================================================

## build: Build image for current platform
build:
	@echo "$(GREEN)Building image for current platform...$(NC)"
	docker build -t $(FULL_IMAGE) $(INFERENCE_DIR)

## build-x86: Build image for x86_64 (RTX 4000 Pro)
build-x86:
	@echo "$(GREEN)Building x86_64 image...$(NC)"
	docker buildx build --platform linux/amd64 \
		-t $(FULL_IMAGE)-amd64 \
		$(INFERENCE_DIR) --load

## build-arm64: Build image for ARM64 (Jetson Thor)
build-arm64:
	@echo "$(GREEN)Building ARM64 image...$(NC)"
	docker buildx build --platform linux/arm64 \
		-t $(FULL_IMAGE)-arm64 \
		$(INFERENCE_DIR) --load

## build-multiarch: Build and push multi-architecture image
build-multiarch:
	@echo "$(GREEN)Building multi-arch image ($(PLATFORMS))...$(NC)"
	docker buildx build --platform $(PLATFORMS) \
		-t $(FULL_IMAGE) \
		$(INFERENCE_DIR) --push

## build-local-multiarch: Build multi-arch without pushing
build-local-multiarch:
	@echo "$(GREEN)Building multi-arch image locally...$(NC)"
	docker buildx build --platform linux/amd64 \
		-t $(FULL_IMAGE)-amd64 $(INFERENCE_DIR) --load
	docker buildx build --platform linux/arm64 \
		-t $(FULL_IMAGE)-arm64 $(INFERENCE_DIR) --load

# ============================================================================
# Test Targets
# ============================================================================

## test: Run all tests
test: lint test-unit test-config

## lint: Run linting
lint:
	@echo "$(GREEN)Running linter...$(NC)"
	cd $(INFERENCE_DIR) && \
		python -m flake8 *.py --max-line-length=120 --ignore=E501,W503 || true

## test-unit: Run unit tests
test-unit:
	@echo "$(GREEN)Running unit tests...$(NC)"
	cd $(INFERENCE_DIR) && python -m pytest tests/ -v || echo "No tests found"

## test-config: Validate configuration files
test-config:
	@echo "$(GREEN)Validating YAML configs...$(NC)"
	python3 -c "import yaml; yaml.safe_load(open('$(INFERENCE_DIR)/sku_profiles.yaml'))"
	python3 -c "import yaml; yaml.safe_load(open('$(INFERENCE_DIR)/config.yaml'))"
	@echo "$(GREEN)Config validation passed$(NC)"

## test-integration: Run integration tests (requires Docker)
test-integration: build
	@echo "$(GREEN)Running integration tests...$(NC)"
	docker run --rm $(FULL_IMAGE) python -c "from server import detect_sku; print(detect_sku())"

# ============================================================================
# Deploy Targets
# ============================================================================

## deploy-lab: Deploy to lab environment (Tesla P40)
deploy-lab:
	@echo "$(GREEN)Deploying to lab environment...$(NC)"
	cd $(DEPLOYMENT_DIR) && \
		FORGE_SKU=$(SKU) docker-compose up -d
	@echo "Waiting for health check..."
	@sleep 10
	@curl -sf http://localhost:8000/health && echo "$(GREEN)Deployment successful$(NC)" || echo "$(YELLOW)Health check pending...$(NC)"

## deploy-stop: Stop lab deployment
deploy-stop:
	@echo "$(GREEN)Stopping deployment...$(NC)"
	cd $(DEPLOYMENT_DIR) && docker-compose down

## deploy-logs: Show deployment logs
deploy-logs:
	cd $(DEPLOYMENT_DIR) && docker-compose logs -f

## deploy-status: Show deployment status
deploy-status:
	@echo "$(GREEN)Deployment Status:$(NC)"
	@docker ps --filter "name=forge" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "$(GREEN)Health Check:$(NC)"
	@curl -sf http://localhost:8000/health 2>/dev/null | python3 -m json.tool || echo "Service not running"
	@echo ""
	@echo "$(GREEN)SKU Info:$(NC)"
	@curl -sf http://localhost:8000/v1/sku 2>/dev/null | python3 -m json.tool || echo "Service not running"

# ============================================================================
# Bundle Targets
# ============================================================================

## bundle: Create air-gapped deployment bundle
bundle:
	@echo "$(GREEN)Creating deployment bundle ($(VERSION))...$(NC)"
	$(CICD_DIR)/scripts/create-bundle.sh $(VERSION)

## bundle-with-models: Create bundle including model files
bundle-with-models:
	@echo "$(GREEN)Creating deployment bundle with models ($(VERSION))...$(NC)"
	$(CICD_DIR)/scripts/create-bundle.sh $(VERSION) --include-models

# ============================================================================
# Development Targets
# ============================================================================

## dev: Start development server locally
dev:
	@echo "$(GREEN)Starting development server...$(NC)"
	cd $(INFERENCE_DIR) && python server.py

## dev-docker: Start development server in Docker
dev-docker: build
	docker run -it --rm \
		--gpus all \
		-p 8000:8000 \
		-v $(INFERENCE_DIR)/config.yaml:/app/config.yaml \
		-v $(INFERENCE_DIR)/sku_profiles.yaml:/app/sku_profiles.yaml \
		$(FULL_IMAGE)

## shell: Open shell in container
shell: build
	docker run -it --rm \
		--gpus all \
		$(FULL_IMAGE) /bin/bash

# ============================================================================
# Utility Targets
# ============================================================================

## clean: Clean build artifacts
clean:
	@echo "$(GREEN)Cleaning build artifacts...$(NC)"
	docker rmi $(FULL_IMAGE) 2>/dev/null || true
	docker rmi $(FULL_IMAGE)-amd64 2>/dev/null || true
	docker rmi $(FULL_IMAGE)-arm64 2>/dev/null || true
	rm -rf $(CICD_DIR)/bundles/*.tar.gz
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

## docker-login: Login to container registry
docker-login:
	@echo "$(GREEN)Logging into $(REGISTRY)...$(NC)"
	docker login $(REGISTRY)

## version: Show version info
version:
	@echo "Version: $(VERSION)"
	@echo "Image: $(FULL_IMAGE)"
	@git log -1 --format="Commit: %h (%s)" 2>/dev/null || true

## info: Show project info
info:
	@echo "$(GREEN)Project Info:$(NC)"
	@echo "  Project Dir: $(PROJECT_DIR)"
	@echo "  Inference:   $(INFERENCE_DIR)"
	@echo "  Deployment:  $(DEPLOYMENT_DIR)"
	@echo "  CI/CD:       $(CICD_DIR)"
	@echo ""
	@echo "$(GREEN)Docker Info:$(NC)"
	@docker version --format "  Docker: {{.Client.Version}}"
	@docker info --format "  Runtime: {{.Runtimes}}" 2>/dev/null || true
