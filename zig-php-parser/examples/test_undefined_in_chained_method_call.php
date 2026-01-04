<?php
// Test undefined variable in chained method call
$obj = new stdClass();
$obj->method1()->method2($undefined_var)->method3();
echo "Done\n";