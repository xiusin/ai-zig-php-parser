<?php
// Test 184: Named arguments
function namedTest(string $name, int $age, bool $active = true): string {
    return "name=$name, age=$age, active=" . ($active ? 'yes' : 'no');
}

echo "=== Named arguments ===\n";
echo namedTest(name: 'Alice', age: 30) . "\n";
echo namedTest(age: 25, name: 'Bob') . "\n";