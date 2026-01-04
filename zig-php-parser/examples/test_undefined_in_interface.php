<?php
// Test undefined variable in interface implementation
interface TestInterface {
    public function testMethod($param);
}
class TestClass implements TestInterface {
    public function testMethod($param) {
        echo $param . "\n";
    }
}
$obj = new TestClass();
$obj->testMethod($undefined_var);
echo "Done\n";
