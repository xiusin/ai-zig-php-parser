<?php

// Test array_first and array_last functions
$numbers = [1, 2, 3, 4, 5];

echo "Testing array_first:\n";
echo array_first($numbers) . "\n";

echo "Testing array_last:\n";
echo array_last($numbers) . "\n";

// Test array_first with callback
echo "First even number: ";
echo array_first($numbers, function($n) { return $n % 2 == 0; }) . "\n";

// Test array_last with callback
echo "Last odd number: ";
echo array_last($numbers, function($n) { return $n % 2 == 1; }) . "\n";

// Test URI functions
echo "Testing URI parsing:\n";
$uri = uri_parse("https://example.com:8080/path?query=value#fragment");
print_r($uri);

echo "Testing URI building:\n";
$components = [
    'scheme' => 'https',
    'host' => 'test.com',
    'port' => 443,
    'path' => '/api/v1',
    'query' => 'key=value'
];
echo uri_build($components) . "\n";