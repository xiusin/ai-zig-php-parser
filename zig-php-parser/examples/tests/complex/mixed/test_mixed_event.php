<?php
class EventEmitter {
    private $listeners = [];

    public function on($event, $callback) {
        $this->listeners[$event][] = $callback;
    }

    public function emit($event, ...$args) {
        if (isset($this->listeners[$event])) {
            foreach ($this->listeners[$event] as $listener) {
                $listener(...$args);
            }
        }
    }
}

$emitter = new EventEmitter();

$emitter->on("user.created", function($user) {
    echo "Welcome, " . $user["name"] . "!\n";
});

$emitter->on("user.created", function($user) {
    echo "Sending email to " . $user["email"] . "...\n";
});

$emitter->on("order.placed", function($order) {
    echo "Order #" . $order["id"] . " placed!\n";
});

$emitter->emit("user.created", [
    "name" => "Alice",
    "email" => "alice@example.com"
]);

$emitter->emit("order.placed", [
    "id" => 12345,
    "total" => 99.99
]);
