<?php
// 极度混搭: 类型推断系统 + Hindley-Milner简化 + 类型约束 + 统一
echo "=== f072: Type Inference + Hindley-Milner ===\n";

class TypeVar {
    private static int $counter = 0;
    public int $id;
    public ?string $resolved = null;
    public array $constraints = [];

    public function __construct() { $this->id = ++self::$counter; }
    public function __toString(): string { return $this->resolved ?? "T{$this->id}"; }
}

class TypeEnv {
    private array $types = []; // var name → TypeVar or string
    private array $unifications = [];

    public function assign(string $name, mixed $type): void {
        $this->types[$name] = $type;
    }

    public function lookup(string $name): mixed {
        return $this->types[$name] ?? null;
    }

    public function unify(TypeVar $a, TypeVar $b): bool {
        if ($a->resolved !== null && $b->resolved !== null) {
            return $a->resolved === $b->resolved;
        }
        if ($a->resolved !== null && $b->resolved === null) {
            $b->resolved = $a->resolved;
            return true;
        }
        if ($a->resolved === null && $b->resolved !== null) {
            $a->resolved = $b->resolved;
            return true;
        }
        // Both unresolved → alias
        $a->resolved = "T{$b->id}";
        $this->unifications[] = "T{$a->id} ~ T{$b->id}";
        return true;
    }

    public function unifyWithType(TypeVar $var, string $type): bool {
        if ($var->resolved !== null) return $var->resolved === $type;
        $var->resolved = $type;
        return true;
    }

    public function getUnifications(): array { return $this->unifications; }
}

class TypeInferer {
    private TypeEnv $env;
    private array $builtinTypes = [
        'int' => 'int', 'float' => 'float', 'string' => 'string',
        'bool' => 'bool', 'array' => 'array', 'null' => 'null',
    ];

    public function __construct() { $this->env = new TypeEnv(); }

    public function inferLiteral(mixed $value): string {
        return match(gettype($value)) {
            'integer' => 'int',
            'double' => 'float',
            'string' => 'string',
            'boolean' => 'bool',
            'array' => 'array',
            'NULL' => 'null',
            default => 'unknown',
        };
    }

    public function inferBinaryOp(string $leftType, string $rightType, string $op): string {
        return match($op) {
            '+', '-', '*', '/', '%' => $this->numericResult($leftType, $rightType),
            '.' => 'string',
            '==', '!=', '<', '>', '<=', '>=', '===', '!==' => 'bool',
            '&&', '||', '!' => 'bool',
            '&' => 'int', '|' => 'int', '^' => 'int',
            default => 'unknown',
        };
    }

    private function numericResult(string $a, string $b): string {
        if ($a === 'float' || $b === 'float') return 'float';
        if ($a === 'int' && $b === 'int') return 'int';
        return 'float';
    }

    public function inferTernary(string $condType, string $trueType, string $falseType): string {
        if ($trueType === $falseType) return $trueType;
        if ($this->isNumeric($trueType) && $this->isNumeric($falseType)) return 'float';
        return 'mixed';
    }

    private function isNumeric(string $type): bool {
        return in_array($type, ['int', 'float']);
    }

    public function inferArray(array $elements): string {
        if (empty($elements)) return 'array';
        $types = array_unique(array_map(fn($e) => $this->inferLiteral($e), $elements));
        $valType = count($types) === 1 ? $types[0] : 'mixed';
        return "array<$valType>";
    }

    public function inferFunctionCall(string $funcName, array $argTypes): string {
        $signatures = [
            'strlen' => ['args' => ['string'], 'return' => 'int'],
            'count' => ['args' => ['array'], 'return' => 'int'],
            'array_sum' => ['args' => ['array'], 'return' => 'int|float'],
            'str_repeat' => ['args' => ['string', 'int'], 'return' => 'string'],
            'implode' => ['args' => ['string', 'array'], 'return' => 'string'],
            'explode' => ['args' => ['string', 'string'], 'return' => 'array'],
            'is_numeric' => ['args' => ['mixed'], 'return' => 'bool'],
            'is_string' => ['args' => ['mixed'], 'return' => 'bool'],
            'is_array' => ['args' => ['mixed'], 'return' => 'bool'],
        ];
        if (isset($signatures[$funcName])) {
            return $signatures[$funcName]['return'];
        }
        return 'mixed';
    }

    public function getEnv(): TypeEnv { return $this->env; }
}

// 测试
$inferer = new TypeInferer();

echo "--- Literal Inference ---\n";
$literals = [42, 3.14, 'hello', true, null, [1, 2, 3]];
foreach ($literals as $lit) {
    $type = $inferer->inferLiteral($lit);
    $val = is_array($lit) ? 'array' : var_export($lit, true);
    echo "  $val → $type\n";
}

echo "\n--- Binary Op Inference ---\n";
$ops = [
    ['int', 'int', '+'],
    ['int', 'float', '*'],
    ['float', 'float', '/'],
    ['string', 'string', '.'],
    ['int', 'int', '=='],
    ['bool', 'bool', '&&'],
];
foreach ($ops as [$l, $r, $op]) {
    $result = $inferer->inferBinaryOp($l, $r, $op);
    echo "  $l $op $r → $result\n";
}

echo "\n--- Ternary Inference ---\n";
$ternaries = [
    ['bool', 'int', 'int'],
    ['bool', 'int', 'float'],
    ['bool', 'string', 'string'],
    ['bool', 'int', 'string'],
];
foreach ($ternaries as [$c, $t, $f]) {
    $result = $inferer->inferTernary($c, $t, $f);
    echo "  $c ? $t : $f → $result\n";
}

echo "\n--- Array Inference ---\n";
$arrays = [
    [1, 2, 3],
    ['a', 'b', 'c'],
    [1, 'two', 3.0],
    [],
];
foreach ($arrays as $arr) {
    $type = $inferer->inferArray($arr);
    $preview = empty($arr) ? '[]' : '[' . implode(', ', array_slice(array_map(fn($x) => is_array($x) ? '...' : var_export($x, true), $arr), 0, 3)) . ']';
    echo "  $preview → $type\n";
}

echo "\n--- Function Call Inference ---\n";
$calls = [
    ['strlen', ['string']],
    ['count', ['array']],
    ['array_sum', ['array']],
    ['str_repeat', ['string', 'int']],
    ['explode', ['string', 'string']],
    ['is_numeric', ['mixed']],
    ['unknown_func', ['mixed']],
];
foreach ($calls as [$func, $args]) {
    $result = $inferer->inferFunctionCall($func, $args);
    echo "  $func(" . implode(', ', $args) . ") → $result\n";
}

echo "\n--- Type Unification ---\n";
$env = $inferer->getEnv();
$v1 = new TypeVar();
$v2 = new TypeVar();
echo "Before: v1=$v1 v2=$v2\n";
$env->unifyWithType($v1, 'int');
echo "After unify v1=int: v1=$v1 v2=$v2\n";
$env->unify($v1, $v2);
echo "After unify v1~v2: v1=$v1 v2=$v2\n";
$v3 = new TypeVar();
$env->unifyWithType($v3, 'string');
$ok = $env->unify($v1, $v3);
echo "Unify int~string: " . var_export($ok, true) . "\n";

echo "\n--- Complex Expression ---\n";
// $result = strlen(str_repeat("ab", 3)) + 5
$inner = $inferer->inferFunctionCall('str_repeat', ['string', 'int']);
$middle = $inferer->inferFunctionCall('strlen', [$inner]);
$outer = $inferer->inferBinaryOp($middle, 'int', '+');
echo "  strlen(str_repeat('ab', 3)) + 5 → $outer\n";

echo "=== f072 Done ===\n";
