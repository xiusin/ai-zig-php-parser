<?php
// 多Trait组合
trait Counter_14 {
    private static $count_14 = 0;
    public static function inc() { return ++self::$count_14; }
    public static function getCount() { return self::$count_14; }
}

trait Logger_14 {
    private $logs_14 = [];
    protected function log($msg) { $this->logs_14[] = $msg; }
    public function getLogs() { return $this->logs_14; }
}

trait Validator_14 {
    protected function validate($val) {
        return $val > 0 && $val < 100;
    }
}

trait Serializer_14 {
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

class Service_14 {
    use Counter_14, Logger_14, Validator_14, Serializer_14;
    
    private $value_14;
    
    public function __construct($v) {
        self::inc();
        $this->value_14 = $v;
        $this->log("Created with value: $v");
    }
    
    public function process($input) {
        $this->log("Processing: $input");
        if (!$this->validate($input)) {
            $this->log("Validation failed");
            return false;
        }
        $this->log("Validation passed");
        return $this->value_14 + $input;
    }
}

$s = new Service_14(23);
echo $s->process(4) . "
";
echo Service_14::getCount() . "
";
echo count($s->getLogs()) . "
";
