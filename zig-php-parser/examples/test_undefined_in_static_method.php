<?php
// Test undefined variable in static method call
class Test {
    public static function testMethod($param) {
        echo $param . "\n";
    }
}
Test::testMethod($undefined_var);
echo "Done\n";