<?php

class Test {
    public function getArray() {
        return [1, 2, 3];
    }

    public function method() {
        $arr = $this->getArray();
        $result = array_map(fn($x) => $x * 2, $arr);
        return $result;
    }

    public function other() {
        return 42;
    }
}

$obj = new Test();
$result = $obj->method();
echo "Result: ";
print_r($result);

$result2 = $obj->other();
echo "Other: $result2\n";

echo "Done\n";
