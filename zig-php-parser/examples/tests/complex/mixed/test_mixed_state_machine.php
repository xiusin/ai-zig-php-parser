<?php
class StateMachine {
    private $states = [];
    private $current;
    private $transitions = [];

    public function addState($name) {
        $this->states[] = $name;
        if ($this->current === null) {
            $this->current = $name;
        }
    }

    public function addTransition($from, $to, $action) {
        $this->transitions[$from][$to] = $action;
    }

    public function canTransition($to) {
        return isset($this->transitions[$this->current][$to]);
    }

    public function transition($to) {
        if ($this->canTransition($to)) {
            $action = $this->transitions[$this->current][$to];
            $action();
            $this->current = $to;
            return true;
        }
        return false;
    }

    public function getState() {
        return $this->current;
    }
}

$machine = new StateMachine();
$machine->addState("pending");
$machine->addState("processing");
$machine->addState("completed");
$machine->addState("failed");

$machine->addTransition("pending", "processing", fn() => echo "Starting process...\n");
$machine->addTransition("processing", "completed", fn() => echo "Process done!\n");
$machine->addTransition("processing", "failed", fn() => echo "Process failed!\n");
$machine->addTransition("failed", "pending", fn() => echo "Retrying...\n");

echo "Initial state: " . $machine->getState() . "\n";
$machine->transition("processing");
echo "After transition: " . $machine->getState() . "\n";
$machine->transition("completed");
echo "Final state: " . $machine->getState() . "\n";
