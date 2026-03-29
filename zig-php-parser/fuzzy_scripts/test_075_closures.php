<?php
// Test 075: Anonymous functions and closures
class ClosureTest {
    public function process(): string {
        $out = "";

        $add = fn(int $a, int $b): int => $a + $b;
        $out .= "Arrow add(5, 3): " . $add(5, 3) . "\n";

        $capture = 10;
        $closure = function(int $x) use ($capture): int {
            return $x + $capture;
        };
        $out .= "Closure capture (5 + 10): " . $closure(5) . "\n";

        $byRef = 5;
        $withRef = function(int $x) use (&$byRef): int {
            $byRef *= 2;
            return $x + $byRef;
        };
        $out .= "Closure with ref: " . $withRef(10) . "\n";
        $out .= "Ref after: $byRef\n";

        return $out;
    }
}

$lab = new ClosureTest();
echo $lab->process();

echo "\n=== Closure from return ===\n";
function createMultiplier(int $factor): callable {
    return fn(int $x): int => $x * $factor;
}

$double = createMultiplier(2);
$triple = createMultiplier(3);
echo "double(10): " . $double(10) . "\n";
echo "triple(10): " . $triple(10) . "\n";

echo "\n=== Closure bind ===\n";
class A { public string $name = 'A'; }
class B { public string $name = 'B'; }

$getName = function() { return $this->name; };

$a = new A();
$b = new B();

$fromA = $getName->bindTo($a, A::class);
$fromB = $getName->bindTo($b, B::class);

echo "From A: " . $fromA() . "\n";
echo "From B: " . $fromB() . "\n";

echo "\n=== Closure call ===\n";
$greet = fn(string $name): string => "Hello, $name!";
echo $greet->call(null, 'World') . "\n";