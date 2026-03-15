<?php
// 多Trait组合
trait Counter_15 {
    private static $count_15 = 0;
    public static function inc() { return ++self::$count_15; }
    public static function getCount() { return self::$count_15; }
}

trait Logger_15 {
    private $logs_15 = [];
    protected function log($msg) { $this->logs_15[] = $msg; }
    public function getLogs() { return $this->logs_15; }
}

trait Validator_15 {
    protected function validate($val) {
        return $val > 0 && $val < 100;
    }
}

trait Serializer_15 {
    public function toArray() {
        $ref = new ReflectionObject($this);
        $props = $ref->getProperties();
        $result = [];
        foreach ($props as $prop) {
            $prop->setAccessible(true);
            $result[$prop->getName()] = $prop->getValue($this);
        }
        return $result;
    }
}

class Service_15 {
    use Counter_15, Logger_15, Validator_15, Serializer_15;
    
    private $value_15;
    
    public function __construct($v) {
        self::inc();
        $this->value_15 = $v;
        $this->log("Created with value: $v");
    }
    
    public function process($input) {
        $this->log("Processing: $input");
        if (!$this->validate($input)) {
            $this->log("Validation failed");
            return false;
        }
        $this->log("Validation passed");
        return $this->value_15 + $input;
    }
}

$s = new Service_15(46);
echo $s->process(34) . "
";
echo Service_15::getCount() . "
";
echo count($s->getLogs()) . "
";
