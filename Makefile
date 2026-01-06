# Makefile for the Kiro PHP Interpreter

.PHONY: help build run test clean bench

.DEFAULT_GOAL := help

# Colors for better output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Project variables
PROJECT_DIR := zig-php-parser
EXECUTABLE := $(PROJECT_DIR)/zig-out/bin/php-interpreter
ARGS ?=
MODE ?= Debug

help: ## ✨ Show this help message
	@echo "$(BLUE)╔═══════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║     Kiro PHP Interpreter Makefile     ║$(NC)"
	@echo "$(BLUE)╚═══════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Usage for build:$(NC)"
	@echo "  make build [MODE=ReleaseFast|ReleaseSafe|ReleaseSmall]"
	@echo ""

build: ## 🔨 Build the interpreter (default MODE=Debug)
	@echo "$(GREEN)Building the interpreter in $(MODE) mode...$(NC)"
	@cd $(PROJECT_DIR) && zig build -Doptimize=$(MODE)

run: ## ▶️  Run the interpreter with a script
	@echo "$(GREEN)Running the interpreter...$(NC)"
	@cd $(PROJECT_DIR) && zig build run -- $(ARGS)

test: ## 🧪 Run all unit tests
	@echo "$(GREEN)Running unit tests...$(NC)"
	@cd $(PROJECT_DIR) && zig build test --summary all

clean: ## 🧹 Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(PROJECT_DIR)/zig-out $(PROJECT_DIR)/.zig-cache

bench: ## 🚀 Run benchmark and compatibility tests
	@echo "$(GREEN)Running benchmark and compatibility tests...$(NC)"
	@scripts/bench.sh
