<?php
function complexFunction(
    int $int,
    float $float,
    string $string,
    array $array,
    ?string $nullable = null
) {
    echo "int: $int\n";
    echo "float: $float\n";
    echo "string: $string\n";
    echo "array count: " . count($array) . "\n";
    echo "nullable: " . ($nullable ?? "null") . "\n";
}

complexFunction(42, 3.14, "hello", [1, 2, 3]);
