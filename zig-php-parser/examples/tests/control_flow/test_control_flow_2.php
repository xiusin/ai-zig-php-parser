<?php
// try/catch 测试
try {
    $result = 10 / 0;
} catch (DivisionByZeroError $e) {
    echo "Caught division by zero: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "Caught exception: " . $e->getMessage() . "\n";
} finally {
    echo "Finally block executed\n";
}
?>