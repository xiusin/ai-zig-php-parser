<?php
// Test 157: Class constant inheritance
class ConstBase {
    public const BASE = 'base';
    protected const PROTECTED_BASE = 'protected';
}

class ConstChild extends ConstBase {
    public const CHILD = 'child';
}

echo "=== Constant inheritance ===\n";
echo "BASE: " . ConstChild::BASE . "\n";
echo "CHILD: " . ConstChild::CHILD . "\n";