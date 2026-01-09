<?php
$values = [
    "42",
    "3.14",
    "true",
    "false",
    "null",
    "123abc",
    "abc123",
];

foreach ($values as $value) {
    echo "Value: $value\n";
    echo "  (int): " . (int)$value . "\n";
    echo "  (float): " . (float)$value . "\n";
    echo "  (string): " . (string)$value . "\n";
    echo "  (bool): " . ((bool)$value ? "true" : "false") . "\n";
    echo "  (array): " . json_encode((array)$value) . "\n";
    echo "\n";
}
