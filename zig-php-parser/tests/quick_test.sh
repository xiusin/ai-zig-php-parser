#!/bin/bash
# 快速 AOT 测试（只测试关键场景）

set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0

test_case() {
    local name="$1"
    local code="$2"
    
    echo "$code" > /tmp/test.php
    php /tmp/test.php > /tmp/php.txt 2>&1
    
    rm -rf .zigphp_aot_build
    ./zig-out/bin/php-interpreter --compile --output=/tmp/test_aot /tmp/test.php > /dev/null 2>&1
    /tmp/test_aot > /tmp/aot.txt 2>&1
    
    if diff -q /tmp/php.txt /tmp/aot.txt > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $name"
        echo "  PHP: $(cat /tmp/php.txt)"
        echo "  AOT: $(cat /tmp/aot.txt)"
        FAILED=$((FAILED + 1))
    fi
}

echo "快速 AOT 测试..."

# 基础
test_case "变量" '<?php $x=42; echo $x."\n"; ?>'
test_case "算术" '<?php echo (10+5)."\n"; ?>'
test_case "字符串" '<?php echo "Hello"."\n"; ?>'

# 控制流
test_case "if-else" '<?php if(5>3) echo "yes\n"; else echo "no\n"; ?>'
test_case "while" '<?php $i=0; while($i<3) { echo $i."\n"; $i++; } ?>'
test_case "for" '<?php for($i=0;$i<3;$i++) echo $i."\n"; ?>'

# 函数
test_case "函数" '<?php function f($x){return $x*2;} echo f(5)."\n"; ?>'
test_case "递归" '<?php function f($n){return $n<=1?1:$n*f($n-1);} echo f(5)."\n"; ?>'
test_case "默认参数" '<?php function f($x=10){return $x;} echo f()."\n".f(20)."\n"; ?>'

# 全局变量
test_case "全局变量" '<?php $x=0; function f(){global $x; $x++;} f(); f(); echo $x."\n"; ?>'

# 数组
test_case "数组" '<?php $a=[1,2,3]; echo $a[0]."\n"; ?>'
test_case "二维数组" '<?php $a=[]; $a[0][0]=1; echo $a[0][0]."\n"; ?>'
test_case "三维数组" '<?php $a=[]; $a[0][0][0]=1; echo $a[0][0][0]."\n"; ?>'
test_case "关联数组" '<?php $a=["x"=>10]; echo $a["x"]."\n"; ?>'

# 逻辑
test_case "短路AND" '<?php $x=0; function f(){global $x; $x=1; return true;} false && f(); echo $x."\n"; ?>'
test_case "短路OR" '<?php $x=0; function f(){global $x; $x=1; return false;} true || f(); echo $x."\n"; ?>'

# 三元
test_case "三元" '<?php echo (5>3?"yes":"no")."\n"; ?>'

echo ""
echo "总计: $((PASSED + FAILED))"
echo -e "通过: ${GREEN}$PASSED${NC}"
echo -e "失败: ${RED}$FAILED${NC}"

[ $FAILED -eq 0 ] && echo -e "${GREEN}全部通过！${NC}" || echo -e "${RED}有失败${NC}"
exit $FAILED
