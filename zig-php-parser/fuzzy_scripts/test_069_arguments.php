<?php
// Test 069: Function arguments, default values, variadic
class ArgumentTest {
    public function required(string $a): string {
        return "required: $a";
    }

    public function withDefault(string $a, int $b = 10, bool $c = true): string {
        return "a=$a, b=$b, c=" . ($c ? 'true' : 'false');
    }

    public function nullable(?string $a = null): string {
        return $a ?? 'was_null';
    }

    public function variadic(string $first, ...$rest): string {
        return "first=$first, rest=" . implode(',', $rest);
    }

    public function allVariadic(...$args): string {
        return "count=" . count($args) . ", sum=" . array_sum($args);
    }
}

echo "=== Required arguments ===\n";
$obj = new ArgumentTest();
echo $obj->required('hello') . "\n";

echo "\n=== Default values ===\n";
echo $obj->withDefault('x') . "\n";
echo $obj->withDefault('x', 20) . "\n";
echo $obj->withDefault('x', 20, false) . "\n";

echo "\n=== Nullable ===\n";
echo $obj->nullable() . "\n";
echo $obj->nullable('value') . "\n";

echo "\n=== Variadic ===\n";
echo $obj->variadic('first') . "\n";
echo $obj->variadic('first', 'second', 'third') . "\n";

echo "\n=== All variadic ===\n";
echo $obj->allVariadic() . "\n";
echo $obj->allVariadic(1, 2, 3, 4, 5) . "\n";

echo "\n=== Named arguments ===\n";
echo $obj->withDefault(b: 99, a: 'named') . "\n";
echo $obj->withDefault(c: false, a: 'named', b: 50) . "\n";

echo "\n=== Type declarations ===\n";
function typedArgs(int $a, float $b, string $c, bool $d): string {
    return "int=$a, float=$b, string=$c, bool=" . ($d ? 'true' : 'false');
}

echo typedArgs(1, 2.5, 'str', true) . "\n";

echo "\n=== Return type ===\n";
function returnType(): string {
    return 'returned';
}

function returnNullable(): ?string {
    return null;
}

function returnVoid(): void {
    echo "void function\n";
}

echo returnType() . "\n";
echo returnNullable() . "\n";
returnVoid();