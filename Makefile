# ============================================================================
.PHONY: help setup dev dev-debug dev-verbose build build-verbose build-debug test test-verbose test-debug clean clean-cache clean-build clean-temp clean-all clean-all-extended clean-deep clean-docs clean-logs install run fmt lint bench bench-compare bench-table docker docs debug-info debug-build debug-run debug-test release release-debug release-fast release-small release-all package package-debug package-fast package-small package-all dist dist-debug dist-fast dist-small dist-all cross-linux-x64 cross-linux-arm64 cross-macos-x64 cross-macos-arm64 cross-windows-x64 cross-all cross-release-all cross-package-all
# ============================================================================

# 默认目标
.DEFAULT_GOAL := help

# 颜色定义
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
PURPLE := \033[0;35m
CYAN := \033[0;36m
NC := \033[0m # No Color

# 项目变量
PROJECT_NAME := zig-php-parser
BUILD_DIR := zig-out
CACHE_DIR := .zig-cache
SCRIPTS_DIR := scripts
EXAMPLES_DIR := examples
BENCH_DIR := bench_results
BENCH_SCRIPT := $(SCRIPTS_DIR)/benchmark.sh

# ============================================================================
help: ## 显示帮助信息
	@echo "$(BLUE)╔═══════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║    Zig-PHP-Parser Makefile 命令列表    ║$(NC)"
	@echo "$(BLUE)╚═══════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(GREEN)开发命令:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-18s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)示例:$(NC)"
	@echo "  make setup          # 初始化项目"
	@echo "  make build          # 构建项目"
	@echo "  make test           # 运行测试"
	@echo "  make bench          # 运行性能基准测试"
	@echo "  make bench-compare  # 对比不同版本性能"
	@echo "  make bench-table    # 生成性能对比表格"
	@echo ""

# ============================================================================
# ============================================================================
debug-info: ## 显示调试信息（环境、依赖、文件状态等）
	@echo "$(BLUE)╔═══════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║          项目调试信息                  ║$(NC)"
	@echo "$(BLUE)╚═══════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(CYAN)📋 系统信息:$(NC)"
	@echo "  OS: $(shell uname -s) $(shell uname -m)"
	@echo "  User: $(shell whoami)"
	@echo "  Date: $(shell date)"
	@echo ""
	@echo "$(CYAN)🔧 开发环境:$(NC)"
	@echo "  Zig: $(shell zig version 2>/dev/null || echo '未安装')"
	@echo "  Make: $(shell make --version | head -1)"
	@echo "  Git: $(shell git --version 2>/dev/null || echo '未安装')"
	@echo ""
	@echo "$(CYAN)� 项目状态:$(NC)"
	@echo "  项目目录: $(shell pwd)"
	@echo "  构建目录: $(BUILD_DIR) ($(shell if [ -d "$(BUILD_DIR)" ]; then echo "存在"; else echo "不存在"; fi))"
	@echo "  缓存目录: $(CACHE_DIR) ($(shell if [ -d "$(CACHE_DIR)" ]; then echo "存在"; else echo "不存在"; fi))"
	@echo "  示例目录: $(EXAMPLES_DIR) ($(shell if [ -d "$(EXAMPLES_DIR)" ]; then echo "存在 ($(shell find $(EXAMPLES_DIR) -name "*.php" 2>/dev/null | wc -l) 个文件)"; else echo "不存在"; fi))"
	@echo ""
	@echo "$(CYAN)📊 代码统计:$(NC)"
	@echo "  Zig 文件: $(shell find src -name "*.zig" 2>/dev/null | wc -l) 个"
	@echo "  PHP 示例: $(shell find $(EXAMPLES_DIR) -name "*.php" 2>/dev/null | wc -l) 个"
	@echo "  测试文件: $(shell find src -name "*test*.zig" 2>/dev/null | wc -l) 个"
	@echo "  总代码行数: $(shell find src -name "*.zig" -exec cat {} \; 2>/dev/null | wc -l) 行"
	@echo ""
	@echo "$(CYAN)🔍 最近修改:$(NC)"
	@echo "  Git 状态: $(shell git status --porcelain 2>/dev/null | wc -l) 个文件变更"
	@echo "  最后提交: $(shell git log -1 --oneline 2>/dev/null || echo '无提交记录')"

# ============================================================================
dev-debug: ## 启动开发调试模式（详细输出）
	@echo "$(PURPLE)🔥 启动开发调试模式...$(NC)"
	@echo "$(CYAN)调试信息:$(NC)"
	@echo "  时间: $(shell date)"
	@echo "  工作目录: $(shell pwd)"
	@echo "  Zig版本: $(shell zig version 2>/dev/null || echo '未知')"
	@echo ""
	@echo "$(YELLOW)正在构建并运行 (调试模式)...$(NC)"
	@zig build run -- --help 2>&1

dev-verbose: ## 启动详细开发模式（显示所有步骤）
	@echo "$(PURPLE)🔥 启动详细开发模式...$(NC)"
	@echo "$(CYAN)执行步骤:$(NC)"
	@echo "  1. 检查项目结构..."
	@ls -la | grep -E "(src|examples|scripts)" || echo "  ⚠️  部分目录不存在"
	@echo "  2. 检查构建环境..."
	@zig version >/dev/null 2>&1 && echo "  ✅ Zig 环境正常" || echo "  ❌ Zig 环境异常"
	@echo "  3. 检查依赖文件..."
	@[ -f "build.zig" ] && echo "  ✅ build.zig 存在" || echo "  ❌ build.zig 不存在"
	@[ -f "build.zig.zon" ] && echo "  ✅ build.zig.zon 存在" || echo "  ❌ build.zig.zon 不存在"
	@echo "  4. 启动开发服务器..."
	@echo ""
	@echo "$(YELLOW)正在构建并运行...$(NC)"
	@zig build run -- --help 2>&1

run: ## 运行项目（默认模式）
	@echo "$(GREEN)▶️  运行项目...$(NC)"
	@echo "$(CYAN)运行信息:$(NC)"
	@echo "  时间: $(shell date)"
	@echo "  模式: 默认运行"
	@echo ""
	@zig build run

run-file: ## 运行指定PHP文件 (用法: make run-file FILE=path/to/file.php)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)❌ 错误: 请指定文件路径$(NC)"; \
		echo "$(YELLOW)用法: make run-file FILE=path/to/file.php$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)▶️  运行文件: $(FILE)$(NC)"
	@echo "$(CYAN)文件运行信息:$(NC)"
	@echo "  时间: $(shell date)"
	@echo "  文件: $(FILE)"
	@echo "  存在: $(shell if [ -f "$(FILE)" ]; then echo "是"; else echo "否"; fi)"
	@echo "  大小: $(shell if [ -f "$(FILE)" ]; then ls -lh "$(FILE)" | awk '{print $$5}'; else echo "N/A"; fi)"
	@echo ""
	@echo "$(YELLOW)执行文件...$(NC)"
	@zig build run -- $(FILE)

debug-run: ## 调试运行模式（带详细执行信息）
	@echo "$(PURPLE)▶️  调试运行模式...$(NC)"
	@echo "$(CYAN)调试运行信息:$(NC)"
	@echo "  时间: $(shell date)"
	@echo "  工作目录: $(shell pwd)"
	@echo "  可执行文件: $(BUILD_DIR)/bin/php-interpreter"
	@echo "  文件存在: $(shell if [ -f "$(BUILD_DIR)/bin/php-interpreter" ]; then echo "是"; else echo "否"; fi)"
	@echo ""
	@echo "$(YELLOW)检查可执行文件...$(NC)"
	@if [ ! -f "$(BUILD_DIR)/bin/php-interpreter" ]; then \
		echo "$(RED)❌ 可执行文件不存在，请先运行 'make build'$(NC)"; \
		exit 1; \
	fi
	@echo "  ✅ 可执行文件存在"
	@echo "  📊 文件信息: $(shell ls -lh $(BUILD_DIR)/bin/php-interpreter)"
	@echo ""
	@echo "$(YELLOW)执行调试运行...$(NC)"
	@echo "$(PURPLE)命令:$(NC) ./$(BUILD_DIR)/bin/php-interpreter --help"
	@./$(BUILD_DIR)/bin/php-interpreter --help 2>&1 || echo "$(RED)❌ 执行失败$(NC)"
	@echo ""
	@echo "$(GREEN)✅ 调试运行完成$(NC)"

# ============================================================================
build: ## 构建项目（调试模式）
	@echo "$(GREEN)🔨 构建项目 (调试模式)...$(NC)"
	@echo "$(CYAN)构建信息:$(NC)"
	@echo "  模式: Debug"
	@echo "  时间: $(shell date)"
	@echo "  目标: $(BUILD_DIR)/bin/php-interpreter"
	@echo ""
	@echo "$(YELLOW)执行构建...$(NC)"
	@time zig build 2>&1
	@echo "$(GREEN)✅ 构建完成: $(BUILD_DIR)/bin/php-interpreter$(NC)"
	@echo "$(CYAN)可执行文件信息:$(NC)"
	@ls -lh $(BUILD_DIR)/bin/php-interpreter 2>/dev/null || echo "  ⚠️  可执行文件不存在"

build-verbose: ## 构建项目（详细输出模式）
	@echo "$(GREEN)🔨 详细构建项目 (调试模式)...$(NC)"
	@echo "$(CYAN)构建详情:$(NC)"
	@echo "  模式: Debug (详细输出)"
	@echo "  时间: $(shell date)"
	@echo "  Zig版本: $(shell zig version)"
	@echo "  系统: $(shell uname -s) $(shell uname -m)"
	@echo ""
	@echo "$(YELLOW)执行详细构建...$(NC)"
	@echo "$(PURPLE)Zig 构建命令:$(NC) zig build --verbose"
	@zig build --verbose 2>&1
	@echo ""
	@echo "$(GREEN)✅ 详细构建完成$(NC)"
	@echo "$(CYAN)构建产物:$(NC)"
	@find $(BUILD_DIR) -type f -executable 2>/dev/null | head -5 | while read f; do echo "  📄 $$f"; done

build-debug: ## 构建项目（调试模式 + 调试信息）
	@echo "$(PURPLE)🔨 调试构建模式...$(NC)"
	@echo "$(CYAN)调试构建信息:$(NC)"
	@echo "  模式: Debug (增强调试)"
	@echo "  时间: $(shell date)"
	@echo "  环境变量: $(shell env | grep -E "(ZIG|DEBUG)" | wc -l) 个调试相关变量"
	@echo ""
	@echo "$(YELLOW)检查依赖...$(NC)"
	@zig version >/dev/null 2>&1 && echo "  ✅ Zig 可用" || echo "  ❌ Zig 不可用"
	@[ -f "build.zig" ] && echo "  ✅ build.zig 存在" || echo "  ❌ build.zig 不存在"
	@[ -f "build.zig.zon" ] && echo "  ✅ build.zig.zon 存在" || echo "  ❌ build.zig.zon 不存在"
	@echo ""
	@echo "$(YELLOW)执行调试构建...$(NC)"
	@time zig build -Dverbose 2>&1 || zig build 2>&1
	@echo ""
	@echo "$(GREEN)✅ 调试构建完成$(NC)"

build-release: ## 构建项目（发布模式 - 安全优化）
	@echo "$(GREEN)🚀 构建项目 (发布模式)...$(NC)"
	@zig build -Doptimize=ReleaseSafe

build-fast: ## 构建项目（发布模式 - 性能优化）
	@echo "$(GREEN)⚡ 构建项目 (性能优化)...$(NC)"
	@zig build -Doptimize=ReleaseFast

build-small: ## 构建项目（发布模式 - 体积优化）
	@echo "$(GREEN)📦 构建项目 (体积优化)...$(NC)"
	@zig build -Doptimize=ReleaseSmall

build-all: ## 构建所有优化版本
	@echo "$(GREEN)🔨 构建所有版本...$(NC)"
	@make build
	@make build-release
	@make build-fast
	@make build-small
	@echo "$(GREEN)✅ 所有版本构建完成$(NC)"

# ============================================================================
test: ## 运行所有测试
	@echo "$(GREEN)🧪 运行所有测试...$(NC)"
	@echo "$(CYAN)测试信息:$(NC)"
	@echo "  时间: $(shell date)"
	@echo "  测试模式: 标准测试"
	@echo ""
	@echo "$(YELLOW)执行测试...$(NC)"
	@time zig build test 2>&1
	@echo "$(GREEN)✅ 测试完成$(NC)"

test-verbose: ## 运行测试（详细输出模式）
	@echo "$(GREEN)🧪 详细测试模式...$(NC)"
	@echo "$(CYAN)测试详情:$(NC)"
	@echo "  时间: $(shell date)"
	@echo "  测试模式: 详细输出"
	@echo "  Zig版本: $(shell zig version)"
	@echo ""
	@echo "$(YELLOW)执行详细测试...$(NC)"
	@echo "$(PURPLE)Zig 测试命令:$(NC) zig build test --verbose"
	@time zig build test --verbose 2>&1
	@echo ""
	@echo "$(GREEN)✅ 详细测试完成$(NC)"

test-debug: ## 运行测试（调试模式 + 额外信息）
	@echo "$(PURPLE)🧪 调试测试模式...$(NC)"
	@echo "$(CYAN)调试测试信息:$(NC)"
	@echo "  时间: $(shell date)"
	@echo "  测试模式: 调试增强"
	@echo "  测试文件: $(shell find src -name "*test*.zig" 2>/dev/null | wc -l) 个"
	@echo ""
	@echo "$(YELLOW)检查测试环境...$(NC)"
	@find src -name "*test*.zig" 2>/dev/null | head -5 | while read f; do echo "  📄 发现测试文件: $$f"; done
	@echo "  总测试文件数: $(shell find src -name "*test*.zig" 2>/dev/null | wc -l)"
	@echo ""
	@echo "$(YELLOW)执行调试测试...$(NC)"
	@echo "$(PURPLE)环境变量:$(NC)"
	@env | grep -E "(ZIG|TEST|DEBUG)" | head -5 || echo "  无相关环境变量"
	@echo ""
	@time zig build test 2>&1 || echo "$(RED)❌ 测试失败$(NC)"
	@echo ""
	@echo "$(GREEN)✅ 调试测试完成$(NC)"
	@echo "$(CYAN)测试结果统计:$(NC)"
	@echo "  测试文件: $(shell find src -name "*test*.zig" 2>/dev/null | wc -l) 个"
	@echo "  源码文件: $(shell find src -name "*.zig" 2>/dev/null | wc -l) 个"

test-unit: ## 运行单元测试
	@echo "$(GREEN)📝 运行单元测试...$(NC)"
	@zig build test

test-examples: ## 测试示例文件
	@echo "$(GREEN)📁 测试示例文件...$(NC)"
	@find $(EXAMPLES_DIR) -name "*.php" -exec echo "Testing: {}" \; -exec timeout 5s zig build run -- {} \; 2>/dev/null || echo "  ❌ Failed or timeout"

test-memory: ## 运行内存泄漏测试
	@echo "$(GREEN)🧠 运行内存泄漏测试...$(NC)"
	@zig build leak-check

# ============================================================================
bench: ## 运行性能基准测试
	@echo "$(GREEN)📊 运行性能基准测试...$(NC)"
	@mkdir -p $(BENCH_DIR)
	@if [ ! -f "$(BENCH_SCRIPT)" ]; then \
		echo "$(YELLOW)⚠️  基准测试脚本不存在，创建默认脚本...$(NC)"; \
		make create-bench-script; \
	fi
	@bash $(BENCH_SCRIPT)

bench-compare: ## 对比不同优化模式的性能
	@echo "$(GREEN)🔍 对比不同优化模式的性能...$(NC)"
	@mkdir -p $(BENCH_DIR)
	@echo "$(CYAN)构建并测试不同优化模式...$(NC)"
	@make build-fast
	@mv $(BUILD_DIR) $(BUILD_DIR)_fast
	@make build-release
	@mv $(BUILD_DIR) $(BUILD_DIR)_release
	@make build
	@mv $(BUILD_DIR) $(BUILD_DIR)_debug
	@echo "$(CYAN)运行性能对比...$(NC)"
	@bash $(BENCH_SCRIPT) --compare

bench-table: ## 生成性能对比表格
	@echo "$(GREEN)📋 生成性能对比表格...$(NC)"
	@mkdir -p $(BENCH_DIR)
	@bash $(BENCH_SCRIPT) --table > $(BENCH_DIR)/benchmark_table.md
	@echo "$(GREEN)✅ 表格已生成: $(BENCH_DIR)/benchmark_table.md$(NC)"
	@cat $(BENCH_DIR)/benchmark_table.md

bench-custom: ## 运行自定义基准测试 (用法: make bench-custom SCRIPT=path/to/script.php ITERATIONS=100)
	@if [ -z "$(SCRIPT)" ]; then \
		echo "$(RED)❌ 错误: 请指定脚本路径$(NC)"; \
		echo "$(YELLOW)用法: make bench-custom SCRIPT=path/to/script.php ITERATIONS=100$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)📊 运行自定义基准测试...$(NC)"
	@ITERATIONS=$(ITERATIONS) SCRIPT=$(SCRIPT) bash $(BENCH_SCRIPT) --custom

create-bench-script: ## 创建基准测试脚本
	@echo "$(GREEN)📝 创建基准测试脚本...$(NC)"
	@mkdir -p $(SCRIPTS_DIR)
	@echo '#!/bin/bash' > $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo 'set -e' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '# PHP Parser Benchmark Script' >> $(BENCH_SCRIPT)
	@echo '# Usage: ./benchmark.sh [--compare] [--table] [--custom]' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' >> $(BENCH_SCRIPT)
	@echo 'PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"' >> $(BENCH_SCRIPT)
	@echo 'BENCH_DIR="$PROJECT_ROOT/bench_results"' >> $(BENCH_SCRIPT)
	@echo 'PHP_INTERPRETER="$PROJECT_ROOT/zig-out/bin/php-interpreter"' >> $(BENCH_SCRIPT)
	@echo 'EXAMPLES_DIR="$PROJECT_ROOT/examples"' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo 'mkdir -p "$BENCH_DIR"' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo 'run_benchmark() {' >> $(BENCH_SCRIPT)
	@echo '    local name="$1"' >> $(BENCH_SCRIPT)
	@echo '    local script="$2"' >> $(BENCH_SCRIPT)
	@echo '    local iterations="${3:-10}"' >> $(BENCH_SCRIPT)
	@echo '    local output_file="$BENCH_DIR/${name}_$(date +%Y%m%d_%H%M%S).log"' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    echo "Running benchmark: $name"' >> $(BENCH_SCRIPT)
	@echo '    echo "Script: $script"' >> $(BENCH_SCRIPT)
	@echo '    echo "Iterations: $iterations"' >> $(BENCH_SCRIPT)
	@echo '    echo "Output: $output_file"' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    local total_time=0' >> $(BENCH_SCRIPT)
	@echo '    local total_memory=0' >> $(BENCH_SCRIPT)
	@echo '    local success_count=0' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    for i in $(seq 1 $iterations); do' >> $(BENCH_SCRIPT)
	@echo '        echo -n "  Iteration $i/$iterations... "' >> $(BENCH_SCRIPT)
	@echo '        local start_time=$(date +%s%N)' >> $(BENCH_SCRIPT)
	@echo '        if timeout 30s "$PHP_INTERPRETER" "$script" >> "$output_file" 2>&1; then' >> $(BENCH_SCRIPT)
	@echo '            local end_time=$(date +%s%N)' >> $(BENCH_SCRIPT)
	@echo '            local duration=$(( (end_time - start_time) / 1000000 ))' >> $(BENCH_SCRIPT)
	@echo '            total_time=$((total_time + duration))' >> $(BENCH_SCRIPT)
	@echo '            success_count=$((success_count + 1))' >> $(BENCH_SCRIPT)
	@echo '            echo "✓ ($duration ms)"' >> $(BENCH_SCRIPT)
	@echo '        else' >> $(BENCH_SCRIPT)
	@echo '            echo "✗ (failed)"' >> $(BENCH_SCRIPT)
	@echo '        fi' >> $(BENCH_SCRIPT)
	@echo '    done' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    if [ $success_count -gt 0 ]; then' >> $(BENCH_SCRIPT)
	@echo '        local avg_time=$((total_time / success_count))' >> $(BENCH_SCRIPT)
	@echo '        echo "$name,$iterations,$success_count,$avg_time" >> "$BENCH_DIR/results.csv"' >> $(BENCH_SCRIPT)
	@echo '        echo "Results: $success_count/$iterations successful, avg time: ${avg_time}ms"' >> $(BENCH_SCRIPT)
	@echo '    else' >> $(BENCH_SCRIPT)
	@echo '        echo "$name,$iterations,0,0" >> "$BENCH_DIR/results.csv"' >> $(BENCH_SCRIPT)
	@echo '        echo "Results: 0/$iterations successful"' >> $(BENCH_SCRIPT)
	@echo '    fi' >> $(BENCH_SCRIPT)
	@echo '}' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo 'if [ "$1" = "--compare" ]; then' >> $(BENCH_SCRIPT)
	@echo '    echo "Comparing optimization modes..."' >> $(BENCH_SCRIPT)
	@echo '    echo "Mode,Script,Iterations,Success,Time(ms)" > "$BENCH_DIR/compare_results.csv"' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    # Test Debug mode' >> $(BENCH_SCRIPT)
	@echo '    cd "$PROJECT_ROOT"' >> $(BENCH_SCRIPT)
	@echo '    make build > /dev/null 2>&1' >> $(BENCH_SCRIPT)
	@echo '    echo "Testing Debug mode..."' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "debug_fibonacci" "$EXAMPLES_DIR/fibonacci.php" 5' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "debug_prime" "$EXAMPLES_DIR/prime.php" 5' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    # Test ReleaseSafe mode' >> $(BENCH_SCRIPT)
	@echo '    make build-release > /dev/null 2>&1' >> $(BENCH_SCRIPT)
	@echo '    echo "Testing ReleaseSafe mode..."' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "release_safe_fibonacci" "$EXAMPLES_DIR/fibonacci.php" 5' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "release_safe_prime" "$EXAMPLES_DIR/prime.php" 5' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    # Test ReleaseFast mode' >> $(BENCH_SCRIPT)
	@echo '    make build-fast > /dev/null 2>&1' >> $(BENCH_SCRIPT)
	@echo '    echo "Testing ReleaseFast mode..."' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "release_fast_fibonacci" "$EXAMPLES_DIR/fibonacci.php" 5' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "release_fast_prime" "$EXAMPLES_DIR/prime.php" 5' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    echo "Comparison complete. Results in $BENCH_DIR/compare_results.csv"' >> $(BENCH_SCRIPT)
	@echo 'elif [ "$1" = "--table" ]; then' >> $(BENCH_SCRIPT)
	@echo '    if [ ! -f "$BENCH_DIR/compare_results.csv" ]; then' >> $(BENCH_SCRIPT)
	@echo '        echo "No benchmark results found. Run with --compare first."' >> $(BENCH_SCRIPT)
	@echo '        exit 1' >> $(BENCH_SCRIPT)
	@echo '    fi' >> $(BENCH_SCRIPT)
	@echo '' >> $(BENCH_SCRIPT)
	@echo '    echo "# PHP Parser Performance Comparison"' >> $(BENCH_SCRIPT)
	@echo '    echo ""' >> $(BENCH_SCRIPT)
	@echo '    echo "| Mode | Script | Success Rate | Avg Time (ms) |"' >> $(BENCH_SCRIPT)
	@echo '    echo "|------|--------|--------------|---------------|"' >> $(BENCH_SCRIPT)
	@echo '    tail -n +2 "$BENCH_DIR/compare_results.csv" | while IFS="," read -r mode script iterations success time; do' >> $(BENCH_SCRIPT)
	@echo '        rate="$((success * 100 / iterations))%"' >> $(BENCH_SCRIPT)
	@echo '        echo "| $mode | $script | $rate | $time |"' >> $(BENCH_SCRIPT)
	@echo '    done' >> $(BENCH_SCRIPT)
	@echo '    echo ""' >> $(BENCH_SCRIPT)
	@echo '    echo "Generated at: $(date)"' >> $(BENCH_SCRIPT)
	@echo 'elif [ "$1" = "--custom" ]; then' >> $(BENCH_SCRIPT)
	@echo '    if [ -z "$SCRIPT" ] || [ -z "$ITERATIONS" ]; then' >> $(BENCH_SCRIPT)
	@echo '        echo "Usage: SCRIPT=path ITERATIONS=num ./benchmark.sh --custom"' >> $(BENCH_SCRIPT)
	@echo '        exit 1' >> $(BENCH_SCRIPT)
	@echo '    fi' >> $(BENCH_SCRIPT)
	@echo '    script_name=$(basename "$SCRIPT" .php)' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "custom_$script_name" "$SCRIPT" "$ITERATIONS"' >> $(BENCH_SCRIPT)
	@echo 'else' >> $(BENCH_SCRIPT)
	@echo '    # Default benchmark' >> $(BENCH_SCRIPT)
	@echo '    echo "Mode,Script,Iterations,Success,Time(ms)" > "$BENCH_DIR/results.csv"' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "fibonacci" "$EXAMPLES_DIR/fibonacci.php" 10' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "prime" "$EXAMPLES_DIR/prime.php" 10' >> $(BENCH_SCRIPT)
	@echo '    run_benchmark "array_ops" "$EXAMPLES_DIR/array_operations.php" 10' >> $(BENCH_SCRIPT)
	@echo '    echo "Benchmark complete. Results in $BENCH_DIR/results.csv"' >> $(BENCH_SCRIPT)
	@echo 'fi' >> $(BENCH_SCRIPT)
	@chmod +x $(BENCH_SCRIPT)
	@echo "$(GREEN)✅ 基准测试脚本已创建: $(BENCH_SCRIPT)$(NC)"

# ============================================================================
fmt: ## 格式化代码
	@echo "$(GREEN)✨ 格式化代码...$(NC)"
	@zig fmt .

fmt-check: ## 检查代码格式
	@echo "$(GREEN)🔍 检查代码格式...$(NC)"
	@zig fmt --check .

lint: ## 运行代码检查
	@echo "$(GREEN)🔍 运行代码检查...$(NC)"
	@zig fmt --check .
	@echo "$(GREEN)✅ 代码检查完成$(NC)"

# ============================================================================
clean: ## 清理构建文件
	@echo "$(YELLOW)🧹 清理构建文件...$(NC)"
	@echo "$(CYAN)清理项目:$(NC)"
	@echo "  清理构建目录: $(BUILD_DIR)"
	@rm -rf $(BUILD_DIR) 2>/dev/null || true
	@echo "  清理缓存目录: $(CACHE_DIR)"
	@rm -rf $(CACHE_DIR) 2>/dev/null || true
	@echo "$(GREEN)✅ 构建文件清理完成$(NC)"

clean-cache: ## 清理所有缓存文件（Zig缓存、构建缓存等）
	@echo "$(YELLOW)🧹 清理所有缓存文件...$(NC)"
	@echo "$(CYAN)清理缓存:$(NC)"
	@echo "  清理项目缓存目录: $(CACHE_DIR)"
	@rm -rf $(CACHE_DIR) 2>/dev/null || true
	@echo "  清理Zig全局缓存: ~/.cache/zig"
	@rm -rf ~/.cache/zig 2>/dev/null || true
	@echo "  清理系统临时文件: /tmp/zig-*"
	@rm -rf /tmp/zig-* 2>/dev/null || true
	@echo "  清理DS_Store文件"
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@echo "$(GREEN)✅ 缓存清理完成$(NC)"

clean-build: ## 清理构建产物（只清理构建输出，不清理缓存）
	@echo "$(YELLOW)🧹 清理构建产物...$(NC)"
	@echo "$(CYAN)清理构建产物:$(NC)"
	@echo "  清理构建目录: $(BUILD_DIR)"
	@rm -rf $(BUILD_DIR) 2>/dev/null || true
	@echo "  清理可执行文件: $(BUILD_DIR)/bin/*"
	@rm -rf $(BUILD_DIR)/bin/* 2>/dev/null || true
	@echo "  清理库文件: $(BUILD_DIR)/lib/*"
	@rm -rf $(BUILD_DIR)/lib/* 2>/dev/null || true
	@echo "$(GREEN)✅ 构建产物清理完成$(NC)"

clean-temp: ## 清理临时文件和日志
	@echo "$(YELLOW)🧹 清理临时文件和日志...$(NC)"
	@echo "$(CYAN)清理临时文件:$(NC)"
	@echo "  清理基准结果: $(BENCH_DIR)/*.log $(BENCH_DIR)/*.csv $(BENCH_DIR)/*.md"
	@rm -rf $(BENCH_DIR)/*.log $(BENCH_DIR)/*.csv $(BENCH_DIR)/*.md 2>/dev/null || true
	@echo "  清理测试结果: test_results/"
	@rm -rf test_results/ 2>/dev/null || true
	@echo "  清理系统临时文件: *.tmp *.bak *.swp"
	@find . -name "*.tmp" -o -name "*.bak" -o -name "*.swp" -o -name "*~" -delete 2>/dev/null || true
	@echo "  清理崩溃转储文件: core core.*"
	@rm -f core core.* 2>/dev/null || true
	@echo "$(GREEN)✅ 临时文件清理完成$(NC)"

clean-docs: ## 清理生成的文档
	@echo "$(YELLOW)🧹 清理生成的文档...$(NC)"
	@echo "$(CYAN)清理文档:$(NC)"
	@echo "  清理文档目录: docs/"
	@rm -rf docs/ 2>/dev/null || true
	@echo "  清理zig-cache中的文档: $(CACHE_DIR)/docs"
	@rm -rf $(CACHE_DIR)/docs 2>/dev/null || true
	@echo "$(GREEN)✅ 文档清理完成$(NC)"

clean-logs: ## 清理所有日志文件
	@echo "$(YELLOW)🧹 清理所有日志文件...$(NC)"
	@echo "$(CYAN)清理日志:$(NC)"
	@echo "  清理基准日志: $(BENCH_DIR)/*.log"
	@find $(BENCH_DIR) -name "*.log" -delete 2>/dev/null || true
	@echo "  清理测试日志: test_results/*.log"
	@find test_results -name "*.log" -delete 2>/dev/null || true
	@echo "  清理所有*.log文件"
	@find . -name "*.log" -delete 2>/dev/null || true
	@echo "$(GREEN)✅ 日志清理完成$(NC)"

clean-all: clean clean-temp ## 清理所有生成文件（包括日志和基准结果）
	@echo "$(YELLOW)🧹 清理所有文件...$(NC)"
	@echo "$(CYAN)执行全面清理:$(NC)"
	@echo "  已清理: 构建文件 + 临时文件"
	@echo "$(GREEN)✅ 全部清理完成$(NC)"

clean-all-extended: clean clean-cache clean-temp clean-docs clean-logs ## 扩展清理（缓存+文档+日志+临时文件）
	@echo "$(YELLOW)🧹 执行扩展清理...$(NC)"
	@echo "$(CYAN)扩展清理包括:$(NC)"
	@echo "  ✅ 构建文件"
	@echo "  ✅ 缓存文件"
	@echo "  ✅ 临时文件"
	@echo "  ✅ 文档文件"
	@echo "  ✅ 日志文件"
	@echo "$(GREEN)✅ 扩展清理完成$(NC)"

clean-deep: ## 深度清理（包括系统级缓存和隐藏文件）
	@echo "$(RED)🧹 执行深度清理（警告：这将清理更多系统文件）...$(NC)"
	@echo "$(CYAN)深度清理包括:$(NC)"
	@echo "  清理隐藏文件: .*（除了.git）"
	@find . -name ".*" -not -path "./.git*" -delete 2>/dev/null || true
	@echo "  清理macOS扩展属性: ._AppleDouble"
	@find . -name "._*" -delete 2>/dev/null || true
	@echo "  清理Thumbs.db: Windows缩略图缓存"
	@find . -name "Thumbs.db" -delete 2>/dev/null || true
	@echo "  清理node_modules（如果存在）"
	@rm -rf node_modules/ 2>/dev/null || true
	@echo "$(RED)⚠️  深度清理完成，请谨慎使用$(NC)"

# ============================================================================
docs: ## 生成文档
	@echo "$(GREEN)📚 生成文档...$(NC)"
	@zig build docs
	@echo "$(GREEN)✅ 文档已生成: docs/$(NC)"

install: ## 安装可执行文件到系统
	@echo "$(GREEN)📦 安装可执行文件...$(NC)"
	@zig build install
	@echo "$(GREEN)✅ 安装完成$(NC)"

# ============================================================================
# 发布和分发命令
# ============================================================================

release-debug: ## 构建发布版本（调试模式）
	@echo "$(BLUE)🚀 构建发布版本 (Debug)...$(NC)"
	@echo "$(CYAN)构建信息:$(NC)"
	@echo "  版本: $(shell git describe --tags --abbrev=0 2>/dev/null || echo 'v0.1.0')"
	@echo "  优化: Debug"
	@echo "  时间: $(shell date)"
	@echo ""
	@make build-debug
	@echo "$(GREEN)✅ 发布版本构建完成: $(BUILD_DIR)/bin/php-interpreter$(NC)"

release-fast: ## 构建发布版本（性能优化）
	@echo "$(BLUE)🚀 构建发布版本 (ReleaseFast)...$(NC)"
	@echo "$(CYAN)构建信息:$(NC)"
	@echo "  版本: $(shell git describe --tags --abbrev=0 2>/dev/null || echo 'v0.1.0')"
	@echo "  优化: ReleaseFast"
	@echo "  时间: $(shell date)"
	@echo ""
	@make build-fast
	@echo "$(GREEN)✅ 发布版本构建完成: $(BUILD_DIR)/bin/php-interpreter$(NC)"

release-small: ## 构建发布版本（体积优化）
	@echo "$(BLUE)🚀 构建发布版本 (ReleaseSmall)...$(NC)"
	@echo "$(CYAN)构建信息:$(NC)"
	@echo "  版本: $(shell git describe --tags --abbrev=0 2>/dev/null || echo 'v0.1.0')"
	@echo "  优化: ReleaseSmall"
	@echo "  时间: $(shell date)"
	@echo ""
	@make build-small
	@echo "$(GREEN)✅ 发布版本构建完成: $(BUILD_DIR)/bin/php-interpreter$(NC)"

release-all: ## 构建所有发布版本
	@echo "$(BLUE)🚀 构建所有发布版本...$(NC)"
	@echo "$(CYAN)将构建以下版本:$(NC)"
	@echo "  1. Debug 版本"
	@echo "  2. ReleaseFast 版本"
	@echo "  3. ReleaseSmall 版本"
	@echo ""
	@make release-debug
	@echo ""
	@make release-fast
	@echo ""
	@make release-small
	@echo "$(GREEN)✅ 所有发布版本构建完成$(NC)"

# ============================================================================
package-debug: ## 打包发布版本（调试模式）
	@echo "$(PURPLE)📦 打包发布版本 (Debug)...$(NC)"
	@make release-debug
	@mkdir -p dist
	@VERSION=$$(git describe --tags --abbrev=0 2>/dev/null || echo 'v0.1.0'); \
	ARCH=$$(uname -m); \
	OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	PACKAGE_NAME="$(PROJECT_NAME)-$${VERSION#v}-$${OS}-$${ARCH}-debug"; \
	echo "$(CYAN)打包信息:$(NC)"; \
	echo "  包名: $$PACKAGE_NAME"; \
	echo "  版本: $$VERSION"; \
	echo "  系统: $$OS-$$ARCH"; \
	echo "  优化: Debug"; \
	echo ""; \
	rm -rf "dist/$$PACKAGE_NAME"; \
	mkdir -p "dist/$$PACKAGE_NAME"; \
	cp "$(BUILD_DIR)/bin/php-interpreter" "dist/$$PACKAGE_NAME/"; \
	cp README.md "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
	cp LICENSE "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
	cd dist && tar -czf "$$PACKAGE_NAME.tar.gz" "$$PACKAGE_NAME"; \
	rm -rf "$$PACKAGE_NAME"; \
	echo "$(GREEN)✅ 包已创建: dist/$$PACKAGE_NAME.tar.gz$(NC)"

package-fast: ## 打包发布版本（性能优化）
	@echo "$(PURPLE)📦 打包发布版本 (ReleaseFast)...$(NC)"
	@make release-fast
	@mkdir -p dist
	@VERSION=$$(git describe --tags --abbrev=0 2>/dev/null || echo 'v0.1.0'); \
	ARCH=$$(uname -m); \
	OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	PACKAGE_NAME="$(PROJECT_NAME)-$${VERSION#v}-$${OS}-$${ARCH}"; \
	echo "$(CYAN)打包信息:$(NC)"; \
	echo "  包名: $$PACKAGE_NAME"; \
	echo "  版本: $$VERSION"; \
	echo "  系统: $$OS-$$ARCH"; \
	echo "  优化: ReleaseFast"; \
	echo ""; \
	rm -rf "dist/$$PACKAGE_NAME"; \
	mkdir -p "dist/$$PACKAGE_NAME"; \
	cp "$(BUILD_DIR)/bin/php-interpreter" "dist/$$PACKAGE_NAME/"; \
	cp README.md "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
	cp LICENSE "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
	cd dist && tar -czf "$$PACKAGE_NAME.tar.gz" "$$PACKAGE_NAME"; \
	rm -rf "$$PACKAGE_NAME"; \
	echo "$(GREEN)✅ 包已创建: dist/$$PACKAGE_NAME.tar.gz$(NC)"

package-small: ## 打包发布版本（体积优化）
	@echo "$(PURPLE)📦 打包发布版本 (ReleaseSmall)...$(NC)"
	@make release-small
	@mkdir -p dist
	@VERSION=$$(git describe --tags --abbrev=0 2>/dev/null || echo 'v0.1.0'); \
	ARCH=$$(uname -m); \
	OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	PACKAGE_NAME="$(PROJECT_NAME)-$${VERSION#v}-$${OS}-$${ARCH}-small"; \
	echo "$(CYAN)打包信息:$(NC)"; \
	echo "  包名: $$PACKAGE_NAME"; \
	echo "  版本: $$VERSION"; \
	echo "  系统: $$OS-$$ARCH"; \
	echo "  优化: ReleaseSmall"; \
	echo ""; \
	rm -rf "dist/$$PACKAGE_NAME"; \
	mkdir -p "dist/$$PACKAGE_NAME"; \
	cp "$(BUILD_DIR)/bin/php-interpreter" "dist/$$PACKAGE_NAME/"; \
	cp README.md "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
	cp LICENSE "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
	cd dist && tar -czf "$$PACKAGE_NAME.tar.gz" "$$PACKAGE_NAME"; \
	rm -rf "$$PACKAGE_NAME"; \
	echo "$(GREEN)✅ 包已创建: dist/$$PACKAGE_NAME.tar.gz$(NC)"

package-all: ## 打包所有发布版本
	@echo "$(PURPLE)📦 打包所有发布版本...$(NC)"
	@echo "$(CYAN)将创建以下包:$(NC)"
	@echo "  1. Debug 版本包"
	@echo "  2. ReleaseFast 版本包"
	@echo "  3. ReleaseSmall 版本包"
	@echo ""
	@make package-debug
	@echo ""
	@make package-fast
	@echo ""
	@make package-small
	@echo "$(GREEN)✅ 所有发布包创建完成$(NC)"

# ============================================================================
dist-debug: package-debug ## 创建分发包（调试模式）- 别名
dist-fast: package-fast ## 创建分发包（性能优化）- 别名
dist-small: package-small ## 创建分发包（体积优化）- 别名
dist-all: package-all ## 创建所有分发包 - 别名

# ============================================================================
# 别名定义（为了向后兼容）
# ============================================================================

release: release-fast ## 默认发布版本（性能优化）
package: package-fast ## 默认打包版本（性能优化）
dist: dist-fast ## 默认分发版本（性能优化）

# ============================================================================
# 跨平台编译命令
# ============================================================================

cross-linux-x64: ## 交叉编译到 Linux x64
	@echo "$(PURPLE)🔄 交叉编译到 Linux x64...$(NC)"
	@echo "$(CYAN)目标平台:$(NC) linux-x86_64"
	@echo "$(CYAN)优化级别:$(NC) ReleaseFast"
	@echo ""
	@mkdir -p cross-build/linux-x64
	@echo "$(YELLOW)执行交叉编译...$(NC)"
	@zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast --prefix cross-build/linux-x64
	@echo "$(GREEN)✅ Linux x64 编译完成$(NC)"
	@echo "$(CYAN)输出位置:$(NC) cross-build/linux-x64/bin/php-interpreter"

cross-linux-arm64: ## 交叉编译到 Linux ARM64
	@echo "$(PURPLE)🔄 交叉编译到 Linux ARM64...$(NC)"
	@echo "$(CYAN)目标平台:$(NC) linux-aarch64"
	@echo "$(CYAN)优化级别:$(NC) ReleaseFast"
	@echo ""
	@mkdir -p cross-build/linux-arm64
	@echo "$(YELLOW)执行交叉编译...$(NC)"
	@zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseFast --prefix cross-build/linux-arm64
	@echo "$(GREEN)✅ Linux ARM64 编译完成$(NC)"
	@echo "$(CYAN)输出位置:$(NC) cross-build/linux-arm64/bin/php-interpreter"

cross-macos-x64: ## 交叉编译到 macOS x64
	@echo "$(PURPLE)🔄 交叉编译到 macOS x64...$(NC)"
	@echo "$(CYAN)目标平台:$(NC) macos-x86_64"
	@echo "$(CYAN)优化级别:$(NC) ReleaseFast"
	@echo ""
	@mkdir -p cross-build/macos-x64
	@echo "$(YELLOW)执行交叉编译...$(NC)"
	@zig build -Dtarget=x86_64-macos -Doptimize=ReleaseFast --prefix cross-build/macos-x64
	@echo "$(GREEN)✅ macOS x64 编译完成$(NC)"
	@echo "$(CYAN)输出位置:$(NC) cross-build/macos-x64/bin/php-interpreter"

cross-macos-arm64: ## 交叉编译到 macOS ARM64
	@echo "$(PURPLE)🔄 交叉编译到 macOS ARM64...$(NC)"
	@echo "$(CYAN)目标平台:$(NC) macos-aarch64"
	@echo "$(CYAN)优化级别:$(NC) ReleaseFast"
	@echo ""
	@mkdir -p cross-build/macos-arm64
	@echo "$(YELLOW)执行交叉编译...$(NC)"
	@zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast --prefix cross-build/macos-arm64
	@echo "$(GREEN)✅ macOS ARM64 编译完成$(NC)"
	@echo "$(CYAN)输出位置:$(NC) cross-build/macos-arm64/bin/php-interpreter"

cross-windows-x64: ## 交叉编译到 Windows x64
	@echo "$(PURPLE)🔄 交叉编译到 Windows x64...$(NC)"
	@echo "$(CYAN)目标平台:$(NC) windows-x86_64"
	@echo "$(CYAN)优化级别:$(NC) ReleaseFast"
	@echo ""
	@mkdir -p cross-build/windows-x64
	@echo "$(YELLOW)执行交叉编译...$(NC)"
	@zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast --prefix cross-build/windows-x64
	@echo "$(GREEN)✅ Windows x64 编译完成$(NC)"
	@echo "$(CYAN)输出位置:$(NC) cross-build/windows-x64/bin/php-interpreter.exe"

cross-all: ## 交叉编译到所有支持的平台
	@echo "$(PURPLE)🔄 交叉编译到所有平台...$(NC)"
	@echo "$(CYAN)将编译到以下平台:$(NC)"
	@echo "  1. Linux x64"
	@echo "  2. Linux ARM64"
	@echo "  3. macOS x64"
	@echo "  4. macOS ARM64"
	@echo "  5. Windows x64"
	@echo ""
	@make cross-linux-x64
	@echo ""
	@make cross-linux-arm64
	@echo ""
	@make cross-macos-x64
	@echo ""
	@make cross-macos-arm64
	@echo ""
	@make cross-windows-x64
	@echo "$(GREEN)✅ 所有平台编译完成$(NC)"

# ============================================================================
# 跨平台发布和打包
# ============================================================================

cross-release-all: cross-all ## 构建所有平台的发布版本
	@echo "$(GREEN)✅ 所有平台的发布版本已构建完成$(NC)"
	@echo "$(CYAN)构建产物位置:$(NC) cross-build/"
	@find cross-build -name "php-interpreter*" -type f | while read f; do echo "  📄 $$f"; done

cross-package-all: cross-release-all ## 打包所有平台的发布版本
	@echo "$(PURPLE)📦 打包所有平台的发布版本...$(NC)"
	@mkdir -p dist
	@echo "$(CYAN)正在创建平台包...$(NC)"
	@VERSION=$$(git describe --tags --abbrev=0 2>/dev/null || echo 'v0.1.0'); \
	for platform in linux-x64 linux-arm64 macos-x64 macos-arm64 windows-x64; do \
		echo "  📦 打包 $$platform..."; \
		PACKAGE_NAME="$(PROJECT_NAME)-$${VERSION#v}-$$platform"; \
		rm -rf "dist/$$PACKAGE_NAME"; \
		mkdir -p "dist/$$PACKAGE_NAME"; \
		if [ "$$platform" = "windows-x64" ]; then \
			cp "cross-build/$$platform/bin/php-interpreter.exe" "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
		else \
			cp "cross-build/$$platform/bin/php-interpreter" "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
		fi; \
		cp README.md "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
		cp LICENSE "dist/$$PACKAGE_NAME/" 2>/dev/null || true; \
		cd dist && tar -czf "$$PACKAGE_NAME.tar.gz" "$$PACKAGE_NAME"; \
		rm -rf "$$PACKAGE_NAME"; \
		echo "    ✅ $$PACKAGE_NAME.tar.gz"; \
	done
	@echo "$(GREEN)✅ 所有平台包创建完成$(NC)"
	@echo "$(CYAN)分发包列表:$(NC)"
	@ls -la dist/*.tar.gz 2>/dev/null | while read line; do echo "  $$line"; done

# ============================================================================
docker-build: ## 构建Docker镜像
	@echo "$(GREEN)🐳 构建Docker镜像...$(NC)"
	@if [ ! -f "Dockerfile" ]; then \
		echo "$(RED)❌ Dockerfile不存在$(NC)"; \
		exit 1; \
	fi
	@docker build -t $(PROJECT_NAME) .

docker-run: ## 运行Docker容器
	@echo "$(GREEN)🐳 运行Docker容器...$(NC)"
	@docker run --rm -it $(PROJECT_NAME)

# ============================================================================
.PHONY: version
version: ## 显示版本信息
	@echo "$(BLUE)╔═══════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║          Zig-PHP-Parser 版本信息       ║$(NC)"
	@echo "$(BLUE)╚═══════════════════════════════════════╝$(NC)"
	@echo ""
	@zig version
	@echo ""
	@./zig-out/bin/php-interpreter --version 2>/dev/null || echo "可执行文件未构建"
