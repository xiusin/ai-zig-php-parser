<?php
// Anonymous classes and closures
interface Logger {
    public function log($message);
    public function getLogs();
}

function createLogger($prefix = "") {
    return new class($prefix) implements Logger {
        private $prefix;
        private $logs = [];
        
        public function __construct($prefix) {
            $this->prefix = $prefix;
        }
        
        public function log($message) {
            $timestamp = date("Y-m-d H:i:s");
            $this->logs[] = "[{$timestamp}] [{$this->prefix}] {$message}";
        }
        
        public function getLogs() {
            return $this->logs;
        }
    };
}

class Processor {
    private $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function process($data, callable $callback) {
        echo "Processing data with {$this->name}\n";
        $result = $callback($data);
        echo "Result: {$result}\n";
        return $result;
    }
    
    public function getName() {
        return $this->name;
    }
}

// Test anonymous classes
$logger = createLogger("APP");
$logger->log("Application started");
$logger->log("Processing data");
$logger->log("Application finished");

echo "Logs:\n";
foreach ($logger->getLogs() as $log) {
    echo "  {$log}\n";
}

// Test closure binding
$processor = new Processor("DataProcessor");

$closure1 = function($data) {
    return "Processed: " . strtoupper($data);
};

$closure2 = function($data) {
    return "Processed by {$this->name}: " . strtolower($data);
};

$closure3 = function($data) {
    return "Processed: " . strrev($data);
};

$processor->process("Hello World", $closure1);
$processor->process("Hello World", $closure2);
$processor->process("Hello World", $closure3);

// Test closure with use
$multiplier = 5;
$closure4 = function($data) use ($multiplier) {
    return "Multiplied by {$multiplier}: " . ($data * $multiplier);
};

$processor->process(10, $closure4);

// Test anonymous class with closure
$processor2 = new Processor("AdvancedProcessor");

$processor2->process("test", function($data) {
    $logger = new class {
        private $logs = [];
        
        public function log($msg) {
            $this->logs[] = $msg;
        }
        
        public function getLogs() {
            return $this->logs;
        }
    };
    
    $logger->log("Processing: " . $data);
    $logger->log("Transforming: " . $data);
    
    return implode(" | ", $logger->getLogs());
});

echo "Done\n";
