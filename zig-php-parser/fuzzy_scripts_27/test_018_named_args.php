<?php
// Test 018: Named arguments, spread operator, and argument unpacking
class NamedArgsLab {
    public function process(
        string $name,
        int $age = 0,
        bool $active = true,
        array $tags = [],
        ?string $email = null
    ): string {
        return "Name: $name, Age: $age, Active: " . ($active ? 'yes' : 'no') .
               ", Tags: " . implode(',', $tags) . ", Email: " . ($email ?? 'none');
    }

    public function combine(string $first = '', string $second = '', string $third = ''): string {
        return trim("$first $second $third");
    }
}

function globalProcess(
    int $x,
    int $y = 10,
    string $op = 'add',
    bool $verbose = false
): int {
    if ($verbose) echo "Computing $x $op $y\n";
    return match($op) {
        'add' => $x + $y,
        'sub' => $x - $y,
        'mul' => $x * $y,
        'div' => $y != 0 ? intdiv($x, $y) : 0,
        default => 0,
    };
}

$lab = new NamedArgsLab();

echo "=== Named Arguments ===\n";
echo $lab->process(
    name: 'John',
    age: 30,
    tags: ['php', 'developer']
) . "\n";

echo $lab->process(
    email: 'john@example.com',
    name: 'Jane',
    active: false,
    tags: ['designer', 'artist']
) . "\n";

echo $lab->combine(second: 'middle', first: 'First', third: 'Third') . "\n";

echo "\n=== Spread Operator in Arrays ===\n";
$base = [1, 2, 3];
$added = [4, 5];
$combined = [...$base, ...$added];
echo "Combined: " . implode(',', $combined) . "\n";

$head = [0, ...$base];
echo "Prepend 0: " . implode(',', $head) . "\n";

$tail = [...$base, 6];
echo "Append 6: " . implode(',', $tail) . "\n";

echo "\n=== Spread Operator in Function Calls ===\n";
$nums = [1, 2, 3, 4, 5];
echo "max(...nums): " . max(...$nums) . "\n";
echo "min(...nums): " . min(...$nums) . "\n";

function sum(int $a, int $b, int $c, int $d = 0, int $e = 0): int {
    return $a + $b + $c + $d + $e;
}

$numbers = [10, 20, 30];
echo "sum(5, ...numbers): " . sum(5, ...$numbers) . "\n";

echo "\n=== Argument Unpacking with array_map ===\n";
$a = [1, 2, 3];
$b = [10, 20, 30];
$summed = array_map(fn($x, $y) => $x + $y, ...[$a, $b]);
echo "array_map sum: " . implode(',', $summed) . "\n";

echo "\n=== Global function with named args ===\n";
echo globalProcess(x: 10, y: 5, op: 'mul', verbose: true) . "\n";
echo globalProcess(op: 'div', x: 100, y: 7) . "\n";

echo "\n=== Complex unpacking ===\n";
$defaults = ['a' => 1, 'b' => 2, 'c' => 3];
$override = ['b' => 20, 'c' => 30];
$merged = ['a' => 0, ...$defaults, ...$override];
echo "Merged array: " . json_encode($merged) . "\n";

echo "\n=== Function returning array with spread ===\n";
function getNumbers(): array {
    return [100, 200, 300];
}

$withExtra = [...getNumbers(), 400, 500];
echo "Spread function result: " . implode(',', $withExtra) . "\n";

echo "\n=== Named constructor args simulation ===\n";
class Config {
    public function __construct(
        public readonly string $host = 'localhost',
        public readonly int $port = 8080,
        public readonly bool $ssl = false,
        public readonly ?string $username = null
    ) {}
}

$cfg = new Config(
    username: 'admin',
    host: 'example.com',
    ssl: true,
    port: 443
);
echo "Config host: $cfg->host, port: $cfg->port, ssl: " . ($cfg->ssl ? 'yes' : 'no') . ", user: $cfg->username\n";