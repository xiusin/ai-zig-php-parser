<?php
class EventEmitter {
    private array $listeners = [];

    public function on(string $event, callable $listener): self {
        $this->listeners[$event][] = $listener;
        return $this;
    }

    public function off(string $event, callable $listener): self {
        if (isset($this->listeners[$event])) {
            $this->listeners[$event] = array_filter(
                $this->listeners[$event],
                fn($l) => $l !== $listener
            );
        }
        return $this;
    }

    public function emit(string $event, mixed ...$args): void {
        if (isset($this->listeners[$event])) {
            foreach ($this->listeners[$event] as $listener) {
                $listener(...$args);
            }
        }
    }

    public function once(string $event, callable $listener): self {
        $wrapper = function(...$args) use ($listener, $event) {
            $listener(...$args);
            $this->off($event, $wrapper);
        };
        return $this->on($event, $wrapper);
    }
}

$emitter = new EventEmitter();
$counter = 0;

$emitter->on('click', function($x) use (&$counter) { $counter += $x; });
$emitter->on('click', function($x) use (&$counter) { $counter *= $x; });
$emitter->emit('click', 2);
echo $counter . "\n";

$emitter->once('init', function() { echo "Init once!\n"; });
$emitter->emit('init');
$emitter->emit('init');
echo "OK\n";
