#!/bin/bash

set -e

# PHP Parser Benchmark Script
# Usage: ./benchmark.sh [--compare] [--table] [--custom]

SCRIPT_DIR=""
PROJECT_ROOT=""
BENCH_DIR="ROJECT_ROOT/bench_results"
PHP_INTERPRETER="ROJECT_ROOT/zig-out/bin/php-interpreter"
EXAMPLES_DIR="ROJECT_ROOT/examples"

mkdir -p "ENCH_DIR"

run_benchmark() {
    local name=""
    local script=""
    local iterations=""
    local output_file="ENCH_DIR/_.log"

    echo "Running benchmark: ame"
    echo "Script: cript"
    echo "Iterations: terations"
    echo "Output: utput_file"

    local total_time=0
    local total_memory=0
    local success_count=0

    for i in ; do
        echo -n "  Iteration /terations... "
        local start_time=
        if timeout 30s "HP_INTERPRETER" "cript" >> "utput_file" 2>&1; then
            local end_time=
            local duration= / 1000000 ))
            total_time=)
            success_count=)
            echo "✓ (uration ms)"
        else
            echo "✗ (failed)"
        fi
    done

    if [ uccess_count -gt 0 ]; then
        local avg_time=)
        echo "ame,terations,uccess_count,vg_time" >> "ENCH_DIR/results.csv"
        echo "Results: uccess_count/terations successful, avg time: ms"
    else
        echo "ame,terations,0,0" >> "ENCH_DIR/results.csv"
        echo "Results: 0/terations successful"
    fi
}

if [ "" = "--compare" ]; then
    echo "Comparing optimization modes..."
    echo "Mode,Script,Iterations,Success,Time(ms)" > "ENCH_DIR/compare_results.csv"

    # Test Debug mode
    cd "ROJECT_ROOT"
    make build > /dev/null 2>&1
    echo "Testing Debug mode..."
    run_benchmark "debug_fibonacci" "XAMPLES_DIR/fibonacci.php" 5
    run_benchmark "debug_prime" "XAMPLES_DIR/prime.php" 5

    # Test ReleaseSafe mode
    make build-release > /dev/null 2>&1
    echo "Testing ReleaseSafe mode..."
    run_benchmark "release_safe_fibonacci" "XAMPLES_DIR/fibonacci.php" 5
    run_benchmark "release_safe_prime" "XAMPLES_DIR/prime.php" 5

    # Test ReleaseFast mode
    make build-fast > /dev/null 2>&1
    echo "Testing ReleaseFast mode..."
    run_benchmark "release_fast_fibonacci" "XAMPLES_DIR/fibonacci.php" 5
    run_benchmark "release_fast_prime" "XAMPLES_DIR/prime.php" 5

    echo "Comparison complete. Results in ENCH_DIR/compare_results.csv"
elif [ "" = "--table" ]; then
    if [ ! -f "ENCH_DIR/compare_results.csv" ]; then
        echo "No benchmark results found. Run with --compare first."
        exit 1
    fi

    echo "# PHP Parser Performance Comparison"
    echo ""
    echo "| Mode | Script | Success Rate | Avg Time (ms) |"
    echo "|------|--------|--------------|---------------|"
    tail -n +2 "ENCH_DIR/compare_results.csv" | while IFS="," read -r mode script iterations success time; do
        rate=")%"
        echo "| ode | cript | ate | ime |"
    done
    echo ""
    echo "Generated at: "
elif [ "" = "--custom" ]; then
    if [ -z "CRIPT" ] || [ -z "TERATIONS" ]; then
        echo "Usage: SCRIPT=path ITERATIONS=num ./benchmark.sh --custom"
        exit 1
    fi
    script_name="CRIPT" 
    run_benchmark "custom_cript_name" "CRIPT" "TERATIONS"
else
    # Default benchmark
    echo "Mode,Script,Iterations,Success,Time(ms)" > "ENCH_DIR/results.csv"
    run_benchmark "fibonacci" "XAMPLES_DIR/fibonacci.php" 10
    run_benchmark "prime" "XAMPLES_DIR/prime.php" 10
    run_benchmark "array_ops" "XAMPLES_DIR/array_operations.php" 10
    echo "Benchmark complete. Results in ENCH_DIR/results.csv"
fi
