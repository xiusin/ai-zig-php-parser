<?php
// 测试52: 联合类型与交集类型
type StringOrInt = string|int;
type NullableArray = array|null;

function process(StringOrInt $input): string {
    return match(true) {
        is_string($input) => "String: $input",
        is_int($input) => "Int: $input",
    };
}

echo process("hello") . "\n";
echo process(42) . "\n";

// 可空类型是联合的简写
function nullable(?string $s): void {
    echo $s ?? "null\n";
}
nullable("test");
nullable(null);

// false类型
function parseInt(string $s): int|false {
    return is_numeric($s) ? (int)$s : false;
}
$result = parseInt("123");
if ($result !== false) {
    echo "Parsed: $result\n";
}

// 复杂返回类型
function findUser(int $id): array|null {
    return $id > 0 ? ['id' => $id, 'name' => 'User'] : null;
}
$user = findUser(1);
echo $user ? $user['name'] : "Not found";
echo "\n";
?>