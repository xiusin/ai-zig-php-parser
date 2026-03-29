<?php
// Test 162: Type hinting with objects
class TypeHint {
    public function process(stdClass $obj): string {
        return "stdClass: " . get_class($obj);
    }

    public function processArray(array $arr): int {
        return count($arr);
    }

    public function processString(string $str): int {
        return strlen($str);
    }

    public function processInt(int $num): int {
        return $num * 2;
    }

    public function processBool(bool $flag): string {
        return $flag ? 'true' : 'false';
    }
}

$obj = new TypeHint();
$std = new stdClass();
echo "stdClass: " . $obj->process($std) . "\n";
echo "Array count: " . $obj->processArray([1, 2, 3]) . "\n";
echo "String len: " . $obj->processString('hello') . "\n";
echo "Int doubled: " . $obj->processInt(21) . "\n";
echo "Bool: " . $obj->processBool(true) . "\n";