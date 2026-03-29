<?php
class Observer {
    private array $observers = [];

    public function attach(callable $callback): self {
        $this->observers[] = $callback;
        return $this;
    }

    public function notify(mixed $data): void {
        foreach ($this->observers as $observer) {
            $observer($data);
        }
    }

    public function count(): int {
        return count($this->observers);
    }
}

$observer = new Observer();
$results = [];

$observer->attach(function($data) use (&$results) {
    $results[] = "Observer1 received: $data";
});

$observer->attach(function($data) use (&$results) {
    $results[] = "Observer2 received: $data";
});

$observer->attach(function($data) use (&$results) {
    $results[] = "Observer3 received: $data";
});

$observer->notify("test message");

echo $observer->count() . "\n";
foreach ($results as $r) {
    echo $r . "\n";
}
echo "OK\n";
