<?php
// Test undefined variable in static property access
class Test {
    public static $prop;
}
Test::$prop = $undefined_var;
echo "Done\n";
