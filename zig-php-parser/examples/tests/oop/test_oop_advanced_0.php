<?php
trait CanEat {
    public function eat($food) {
        return "Eating " . $food;
    }
}

trait CanSleep {
    public function sleep($hours) {
        return "Sleeping for " . $hours . " hours";
    }
}

trait CanWork {
    public function work($task) {
        return "Working on " . $task;
    }
}

class Human {
    use CanEat, CanSleep, CanWork;
    private $name;
    private $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function getInfo() {
        return $this->name . " is " . $this->age . " years old";
    }
}

$human = new Human("Alice", 30);
echo $human->getInfo() . "\n";
echo $human->eat("apple") . "\n";
echo $human->sleep(8) . "\n";
echo $human->work("project") . "\n";
?>