#!/bin/bash
# 基准测试运行脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCHMARKS_DIR="$SCRIPT_DIR"
BUILD_DIR="/tmp/php_aot_benchmarks"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== PHP AOT Compiler Benchmarks ===${NC}\n"

# 清理构建目录
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 编译器路径
COMPILER="$PROJECT_ROOT/zig-out/bin/php-interpreter"

if [ ! -f "$COMPILER" ]; then
    echo -e "${RED}Error: Compiler not found at $COMPILER${NC}"
    echo "Please run 'zig build' first"
    exit 1
fi

# 运行单个基准测试
run_benchmark() {
    local name=$1
    local file=$2
    local optimize=${3:-release-safe}
    
    echo -e "${YELLOW}Running: $name (optimize=$optimize)${NC}"
    
    # 编译
    local output="$BUILD_DIR/${name}_${optimize}"
    if ! "$COMPILER" --compile --optimize="$optimize" --output="$output" "$file" 2>&1 | grep -q "Success"; then
        echo -e "${RED}  Compilation failed${NC}"
        return 1
    fi
    
    # 运行
    echo -e "${GREEN}  AOT ($optimize):${NC}"
    "$output"
    echo ""
}

# 微基准测试
echo -e "${BLUE}=== Micro Benchmarks ===${NC}\n"

if [ -d "$BENCHMARKS_DIR/micro" ]; then
    for file in "$BENCHMARKS_DIR/micro"/*.php; do
        if [ -f "$file" ]; then
            name=$(basename "$file" .php)
            
            # 测试不同优化级别
            run_benchmark "$name" "$file" "debug"
            run_benchmark "$name" "$file" "release-safe"
            run_benchmark "$name" "$file" "release-fast"
        fi
    done
fi

# 清理
rm -rf "$BUILD_DIR"

echo -e "${BLUE}=== Benchmarks Complete ===${NC}"
