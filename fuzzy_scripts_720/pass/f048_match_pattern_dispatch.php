<?php
// 极度混搭: match表达式 + switch对比 + 模式匹配 + 条件分派 + 严格比较
echo "=== f048: Match Expression + Pattern Dispatch ===\n";

class HttpRouter {
    public function handle(string $method, string $path): string {
        return match([$method, $path]) {
            ['GET', '/'] => 'Home page',
            ['GET', '/about'] => 'About page',
            ['GET', '/users'] => 'List users',
            ['POST', '/users'] => 'Create user',
            ['GET', '/users/1'] => 'Show user 1',
            ['PUT', '/users/1'] => 'Update user 1',
            ['DELETE', '/users/1'] => 'Delete user 1',
            default => "404: $method $path not found",
        };
    }
}

class TypeMatcher {
    public static function describe(mixed $value): string {
        return match(true) {
            is_int($value) && $value > 0 => "positive integer: $value",
            is_int($value) && $value < 0 => "negative integer: $value",
            is_int($value) => "zero",
            is_float($value) => "float: $value",
            is_string($value) && strlen($value) === 0 => "empty string",
            is_string($value) && strlen($value) < 10 => "short string: '$value'",
            is_string($value) => "long string: '" . substr($value, 0, 10) . "...'",
            is_bool($value) => "boolean: " . var_export($value, true),
            is_array($value) && empty($value) => "empty array",
            is_array($value) && array_is_list($value) => "list array with " . count($value) . " items",
            is_array($value) => "assoc array with " . count($value) . " keys",
            is_null($value) => "null",
            is_object($value) => "object of type " . get_class($value),
            default => "unknown type",
        };
    }

    public static function classify(int $score): string {
        return match(true) {
            $score >= 90 => 'A',
            $score >= 80 => 'B',
            $score >= 70 => 'C',
            $score >= 60 => 'D',
            $score >= 0 => 'F',
            default => 'Invalid',
        };
    }

    public static function getSeason(int $month): string {
        return match($month) {
            12, 1, 2 => 'Winter',
            3, 4, 5 => 'Spring',
            6, 7, 8 => 'Summer',
            9, 10, 11 => 'Fall',
            default => 'Invalid month',
        };
    }

    public static function calculate(float $a, float $b, string $op): float {
        return match($op) {
            '+' => $a + $b,
            '-' => $a - $b,
            '*' => $a * $b,
            '/' => $b == 0 ? throw new InvalidArgumentException("Division by zero") : $a / $b,
            '%' => fmod($a, $b),
            '^' => pow($a, $b),
            default => throw new InvalidArgumentException("Unknown operator: $op"),
        };
    }
}

// 测试
echo "--- HTTP Router ---\n";
$router = new HttpRouter();
$routes = [
    ['GET', '/'], ['GET', '/about'], ['GET', '/users'], ['POST', '/users'],
    ['GET', '/users/1'], ['PUT', '/users/1'], ['DELETE', '/users/1'],
    ['GET', '/unknown'],
];
foreach ($routes as [$m, $p]) {
    echo "  $m $p → " . $router->handle($m, $p) . "\n";
}

echo "\n--- Type Matcher ---\n";
$values = [42, -5, 0, 3.14, '', 'hello', 'this is a long string', true, false, [], [1,2,3], ['a'=>1], null, new stdClass()];
foreach ($values as $v) {
    echo "  " . TypeMatcher::describe($v) . "\n";
}

echo "\n--- Grade Classification ---\n";
$scores = [95, 85, 75, 65, 55, -1];
foreach ($scores as $s) {
    echo "  Score $s → Grade " . TypeMatcher::classify($s) . "\n";
}

echo "\n--- Seasons ---\n";
for ($m = 1; $m <= 12; $m++) {
    echo "  Month $m → " . TypeMatcher::getSeason($m) . "\n";
}

echo "\n--- Calculator (match with exceptions) ---\n";
$ops = [['+', 10, 3], ['-', 10, 3], ['*', 10, 3], ['/', 10, 3], ['/', 10, 0], ['^', 2, 10]];
foreach ($ops as [$op, $a, $b]) {
    try {
        $result = TypeMatcher::calculate($a, $b, $op);
        echo "  $a $op $b = $result\n";
    } catch (InvalidArgumentException $e) {
        echo "  $a $op $b → ERROR: " . $e->getMessage() . "\n";
    }
}

echo "\n--- Switch vs Match ---\n";
$day = 3;
// Switch
$switchResult = '';
switch($day) {
    case 1: $switchResult = 'Monday'; break;
    case 2: $switchResult = 'Tuesday'; break;
    case 3: $switchResult = 'Wednesday'; break;
    case 4: $switchResult = 'Thursday'; break;
    case 5: $switchResult = 'Friday'; break;
    default: $switchResult = 'Weekend';
}
// Match
$matchResult = match($day) {
    1 => 'Monday',
    2 => 'Tuesday',
    3 => 'Wednesday',
    4 => 'Thursday',
    5 => 'Friday',
    default => 'Weekend',
};
echo "  switch($day) = $switchResult\n";
echo "  match($day) = $matchResult\n";

echo "=== f048 Done ===\n";
