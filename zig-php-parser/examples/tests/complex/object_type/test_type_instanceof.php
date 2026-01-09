<?php
class A {}
class B extends A {}
class C {}

$a = new A();
$b = new B();
$c = new C();

echo "a instanceof A: " . ($a instanceof A ? "true" : "false") . "\n";
echo "a instanceof B: " . ($a instanceof B ? "true" : "false") . "\n";
echo "b instanceof A: " . ($b instanceof A ? "true" : "false") . "\n";
echo "b instanceof B: " . ($b instanceof B ? "true" : "false") . "\n";
echo "c instanceof A: " . ($c instanceof A ? "true" : "false") . "\n";
