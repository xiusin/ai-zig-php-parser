<?php
// 未定义变量测试
echo "Testing undefined variables\n";
// 这会生成警告而不是错误
@$undefined_var;
echo "Undefined variable test completed\n";

// 除零错误测试
try {
    $result = 10 / 0;
} catch (DivisionByZeroError $e) {
    echo "Division by zero caught: " . $e->getMessage() . "\n";
}
?>