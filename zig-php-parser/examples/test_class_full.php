<?php
abstract class Base {
    static $foo = "foo";

    public $bar = "bar";
    
    public function __construct() {
        echo "Base\n";
    }

    static function test() {
        echo "test\n";
    }
}

class Derived extends Base {

    public $bar1 = "bar2";

    public $bar2 = "bar2";
	
   
    public function __construct() {
        parent::__construct();
        echo "Derived\n";
        echo  'self::$foo => ' . self::$foo . "\n";
        echo  'self::$bar => ' . $this->bar;
    }
}


$obj = new Derived();

$obj::test();
echo  '$obj::$foo => ' . $obj::$foo;
Derived::test();
echo  'Derived::$foo => ' . Derived::$foo;
echo "\n";