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
}

$obj = new Test();
$result = $obj->method();
echo "Result: ";
print_r($result);

echo "Done\n";
