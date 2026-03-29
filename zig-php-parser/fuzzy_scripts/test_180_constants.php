<?php
// Test 180: Class constant access
class Constants {
    public const VALUE = 100;
    protected const PROTECTED = 200;
}

echo "=== Class constants ===\n";
echo "VALUE: " . Constants::VALUE . "\n";