<?php
// Test 061: Multiple use statements, closure binding
class UseLab {
    public function process(): string {
        $out = "";

        $x = 1;
        $y = 2;
        $z = 3;

        $closure = function() use ($x, $y, $z) {
            return "x=$x, y=$y, z=$z";
        };
        $out .= "Closure with use: " . $closure() . "\n";

        $modify = function() use ($x, &$y, $z) {
            $y = 100;
            return "x=$x, y=$y, z=$z";
        };
        $out .= "Closure with ref: " . $modify() . "\n";
        $out .= "After modify, y: $y\n";

        $obj = new class {
            public string $name = 'anonymous';

            public function getClosure() {
                return function() {
                    return $this->name;
                };
            }

            public function getBoundClosure() {
                return function() {
                    return $this->name;
                };
            }
        };

        $obj2 = new class {
            public string $name = 'other';
        };

        $cl = $obj->getClosure();
        $out .= "Closure without bind: " . $cl() . "\n";

        $bound = Closure::bind($obj->getBoundClosure(), $obj2);
        $out .= "Closure bound to obj2: " . $bound() . "\n";

        return $out;
    }
}

$lab = new UseLab();
echo $lab->process();

echo "\n=== Closure call ===\n";
$greet = function(string $name): string {
    return "Hello, $name!";
};
echo $greet('World') . "\n";
echo $greet->call(null, 'PHP') . "\n";

echo "\n=== Closure bindTo ===\n";
class A {
    public string $name = 'A';
}

class B {
    public string $name = 'B';
}

$getName = function() {
    return $this->name;
};

$a = new A();
$b = new B();

$fromA = $getName->bindTo($a, A::class);
$fromB = $getName->bindTo($b, B::class);
echo "From A: " . $fromA() . "\n";
echo "From B: " . $fromB() . "\n";