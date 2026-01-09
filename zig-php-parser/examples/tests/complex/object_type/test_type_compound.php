<?php
function checkType($value) {
    $checks = [
        "is_null" => is_null($value),
        "is_bool" => is_bool($value),
        "is_int" => is_int($value),
        "is_float" => is_float($value),
        "is_string" => is_string($value),
        "is_array" => is_array($value),
        "is_object" => is_object($value),
        "is_resource" => is_resource($value),
        "is_callable" => is_callable($value),
    ];

    foreach ($checks as $check => $result) {
        if ($result) {
            echo "$check: true\n";
        }
    }
}

checkType(null);
checkType(true);
checkType(42);
checkType(3.14);
checkType("hello");
checkType([1, 2, 3]);
checkType(new stdClass());
