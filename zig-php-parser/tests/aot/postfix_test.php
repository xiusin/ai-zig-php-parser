<?php

class Test {
    public static int $x = 0;
    
    public static function test(): void {
        self::$x++;
        echo "After ++: " . self::$x . "\n";
    }
}

Test::test();
Test::test();
echo "Final: " . Test::$x . "\n";
