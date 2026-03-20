<?php
// Test 126: Named arguments with variadic
function namedVariadic(
    string $name,
    int $age = 0,
    bool $active = true,
    string ...$roles
): string {
    $result = "Name: $name, Age: $age, Active: " . ($active ? 'yes' : 'no');
    if (count($roles) > 0) {
        $result .= ", Roles: " . implode(',', $roles);
    }
    return $result;
}

echo "=== Named arguments with variadic ===\n";
echo namedVariadic(name: 'Bob', age: 30, active: false) . "\n";
echo namedVariadic(name: 'Charlie', roles: 'admin', 'editor', 'viewer') . "\n";
echo namedVariadic('Dave', 25, true, 'user') . "\n";

echo "\n=== Named arguments with defaults ===\n";
echo namedVariadic(name: 'Eve') . "\n";
echo namedVariadic(name: 'Frank', age: 40, roles: 'moderator') . "\n";