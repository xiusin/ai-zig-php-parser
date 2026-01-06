#!/bin/bash

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROJECT_DIR="zig-php-parser"
KIRO_EXECUTABLE="$PROJECT_DIR/zig-out/bin/php-interpreter"
EXAMPLES_DIR="$PROJECT_DIR/examples"

# --- Pre-flight Checks ---
# Check for php executable
if ! command -v php &> /dev/null; then
    echo -e "${RED}Error: 'php' command not found. Please install PHP CLI to run benchmarks.${NC}"
    exit 1
fi

# Ensure the Kiro executable exists by building it first
echo -e "${BLUE}Ensuring Kiro interpreter is built...${NC}"
make build
if [ ! -f "$KIRO_EXECUTABLE" ]; then
    echo -e "${RED}Error: Kiro interpreter executable not found at '$KIRO_EXECUTABLE' after build.${NC}"
    exit 1
fi

# --- Version Information ---
KIRO_VERSION=$($KIRO_EXECUTABLE --version 2>/dev/null || echo "dev")
PHP_VERSION=$(php --version | head -n 1)

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Kiro Benchmark & Comparison         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo -e "Kiro Version: ${YELLOW}$KIRO_VERSION${NC}"
echo -e "PHP Version:  ${YELLOW}$PHP_VERSION${NC}"
echo ""

# --- Table Header ---
printf "%-50s | %-15s | %-15s | %-15s\n" "Script" "Kiro Time (ms)" "PHP Time (ms)" "Status"
printf "%s\n" "----------------------------------------------------|-----------------|-----------------|----------------"

# --- Benchmark Loop ---
find "$EXAMPLES_DIR" -name "*.php" | sort | while read -r script_path; do
    relative_path=$(echo "$script_path" | sed "s|^$PROJECT_DIR/||")

    # Run with Kiro
    kiro_start=$(gdate +%s.%N 2>/dev/null || date +%s.%N)
    kiro_output=$($KIRO_EXECUTABLE "$script_path" 2>&1)
    kiro_exit_code=$?
    kiro_end=$(gdate +%s.%N 2>/dev/null || date +%s.%N)
    kiro_time=$(echo "$kiro_end - $kiro_start" | bc | awk '{printf "%.2f", $1 * 1000}')

    # Run with PHP
    php_start=$(gdate +%s.%N 2>/dev/null || date +%s.%N)
    php_output=$(php "$script_path" 2>&1)
    php_exit_code=$?
    php_end=$(gdate +%s.%N 2>/dev/null || date +%s.%N)
    php_time=$(echo "$php_end - $php_start" | bc | awk '{printf "%.2f", $1 * 1000}')

    # --- Compare and Determine Status ---
    status=""
    if [ $kiro_exit_code -ne 0 ]; then
        status="${RED}Kiro Fail${NC}"
    elif [ $php_exit_code -ne 0 ]; then
        # This case is less likely for standard examples but good to have
        status="${YELLOW}PHP Fail${NC}"
    elif [ "$kiro_output" == "$php_output" ]; then
        status="${GREEN}Success${NC}"
    else
        status="${YELLOW}Mismatch${NC}"
    fi

    printf "%-50s | %-15s | %-15s | %-15b\n" "$relative_path" "$kiro_time" "$php_time" "$status"
done

echo ""
echo -e "${BLUE}Benchmark run complete.${NC}"
