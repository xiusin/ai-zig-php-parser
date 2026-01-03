<?php
class Test {
    public function hello() {
        echo "Hello from method\n";
        return 42;
    }
}
$t = new Test();
echo $t->hello();
echo "\n";
