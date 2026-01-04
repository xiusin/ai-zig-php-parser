<?php
// Simple anonymous class test
interface Logger {
    public function log($message);
    public function getLogs();
}

$logger = new class implements Logger {
    private $logs = [];
    
    public function log($message) {
        $this->logs[] = $message;
    }
    
    public function getLogs() {
        return $this->logs;
    }
};

echo "=== Anonymous Class Testing ===\n";
$logger->log("Message 1");
$logger->log("Message 2");

echo "Logs:\n";
foreach ($logger->getLogs() as $log) {
    echo "  {$log}\n";
}

echo "\nDone\n";
