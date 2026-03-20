<?php
// Test 139: Multiple traits with method resolution
trait T1 {
    public function method(): string {
        return "T1";
    }
}

trait T2 {
    public function method(): string {
        return "T2";
    }
}

trait T3 {
    use T1, T2 {
        T2::method as t2Method;
    }

    public function method(): string {
        return "T3";
    }

    public function callT2(): string {
        return $this->t2Method();
    }
}

class UseMultipleTraits {
    use T3;
}

echo "=== Multiple trait method resolution ===\n";
$obj = new UseMultipleTraits();
echo "method(): " . $obj->method() . "\n";
echo "callT2(): " . $obj->callT2() . "\n";

echo "\n=== Insteadof ===\n";
trait THello {
    public function greet(): string {
        return "Hello";
    }
}

trait TWorld {
    public function greet(): string {
        return "World";
    }
}

class Greeting {
    use THello, TWorld {
        THello::greet as greetHello;
        TWorld::greet as greetWorld;
    }

    public function fullGreet(): string {
        return $this->greetHello() . " " . $this->greetWorld();
    }
}

$g = new Greeting();
echo "fullGreet: " . $g->fullGreet() . "\n";