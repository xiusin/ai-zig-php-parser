<?php
// Test 028: New functions in PHP 8.x and simulated hooks behavior
class PropertyHooksSim {
    private string $_name = '';
    private int $_counter = 0;
    private string $_computed = '';

    public string $name {
        get => $this->_name;
        set(string $value) {
            $this->_name = trim($value);
        }
    }

    public int $counter {
        get => $this->_counter;
        set {
            if ($value < 0) {
                throw new InvalidArgumentException("Counter cannot be negative");
            }
            $this->_counter = $value;
        }
    }

    public string $computed {
        get => strtoupper($this->_computed);
    }

    public function __construct(
        string $name = '',
        int $counter = 0,
        string $computed = ''
    ) {
        $this->_name = trim($name);
        $this->_counter = $counter;
        $this->_computed = $computed;
    }

    public function increment(): void {
        $this->_counter = $this->_counter + 1;
    }
}

class BaseHookSim {
    public string $status = '';

    public function getStatus(): string {
        return $this->status;
    }

    public function setStatus(string $value): void {
        $this->status = $value;
    }
}

class DerivedHookSim extends BaseHookSim {
    public function getStatus(): string {
        return parent::getStatus() . ' (derived)';
    }

    public function setStatus(string $value): void {
        parent::setStatus($value);
    }
}

echo "=== Property hooks simulation ===\n";
$ph = new PropertyHooksSim('  test  ', 10, 'computed value');
echo "Name (after set hook): '" . $ph->name . "'\n";
echo "Counter: " . $ph->counter . "\n";
echo "Computed: " . $ph->computed . "\n";

$ph->name = '  trimmed  ';
$ph->counter = 11;
echo "After modification - Name: '" . $ph->name . "', Counter: " . $ph->counter . "\n";

echo "\n=== Override property hooks simulation ===\n";
$derived = new DerivedHookSim();
$derived->setStatus('active');
echo "Derived status: " . $derived->getStatus() . "\n";

echo "\n=== Hooks with validation ===\n";
$hook = new PropertyHooksSim('init', 0, 'test');
try {
    $hook->counter = -5;
} catch (InvalidArgumentException $e) {
    echo "Caught exception: " . $e->getMessage() . "\n";
}
echo "Counter after failed set: " . $hook->counter . "\n";