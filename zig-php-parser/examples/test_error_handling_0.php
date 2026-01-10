<?php
// 错误处理测试
function risky_function() {
    if (rand(0, 1)) {
        throw new Exception("Something went wrong");
    }
    return "Success";
}

try {
    $result = risky_function();
    echo "Result: $result\n";
} catch (Exception $e) {
    echo "Caught exception: " . $e->getMessage() . "\n";
} finally {
    echo "Finally block executed\n";
}
?>