<?php
class SharedCounter {
    private $value = 0;
    private $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function increment() {
        $this->value = $this->value + 1;
    }
    
    public function getValue() {
        return $this->value;
    }
    
    public function getName() {
        return $this->name;
    }
}

$counter = new SharedCounter("Counter");

for ($i = 0; $i < 5; $i++) {
    $counter->increment();
    echo $counter->getName() . " value after increment " . $i . ": " . $counter->getValue() . "\n";
}

echo "Final " . $counter->getName() . " value: " . $counter->getValue() . "\n";
?>