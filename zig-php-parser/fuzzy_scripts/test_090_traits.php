<?php
// Test 090: Trait conflicts and resolution
trait A {
    public function test(): string {
        return "A::test";
    }
}

trait B {
    public function test(): string {
        return "B::test";
    }
}

class UseTrait {
    use A, B {
        A::test insteadof B;
        B::test as testB;
    }

    public function run(): string {
        return "A: " . $this->test() . ", B: " . $this->testB();
    }
}

echo "=== Trait conflict ===\n";
$obj = new UseTrait();
echo $obj->run() . "\n";

echo "\n=== Multiple traits ===\n";
trait T1 {
    public function t1(): string { return "t1"; }
}

trait T2 {
    public function t2(): string { return "t2"; }
}

class MultiTrait {
    use T1, T2;
}

$m = new MultiTrait();
echo "t1: " . $m->t1() . "\n";
echo "t2: " . $m->t2() . "\n";

echo "\n=== Trait with abstract ===\n";
trait TraitWithAbstract {
    abstract public function getValue(): string;

    public function process(): string {
        return "processed: " . $this->getValue();
    }
}

class AbstractImpl {
    use TraitWithAbstract;

    public function getValue(): string {
        return "value";
    }
}

$impl = new AbstractImpl();
echo "process: " . $impl->process() . "\n";