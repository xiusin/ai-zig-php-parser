<?php
interface Logger {
    public function log($message);
}

class FileLogger implements Logger {
    private $file;

    public function __construct($file) {
        $this->file = $file;
    }

    public function log($message) {
        echo "[File] $message\n";
    }
}

class ConsoleLogger implements Logger {
    public function log($message) {
        echo "[Console] $message\n";
    }
}

class Service {
    private $logger;

    public function __construct(Logger $logger) {
        $this->logger = $logger;
    }

    public function doSomething($task) {
        $this->logger->log("Starting: $task");
        // Simulate work
        $result = strtoupper($task);
        $this->logger->log("Completed: $result");
        return $result;
    }
}

function createService($loggerType) {
    $logger = $loggerType === "file" ? new FileLogger("app.log") : new ConsoleLogger();
    return new Service($logger);
}

$service1 = createService("file");
$service2 = createService("console");

echo "=== File Logger Service ===\n";
$service1->doSomething("process data");

echo "\n=== Console Logger Service ===\n";
$service2->doSomething("send email");
