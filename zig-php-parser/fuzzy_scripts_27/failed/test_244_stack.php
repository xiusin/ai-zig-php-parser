<?php
class Stack {
    private array $items = [];
    private int $top = -1;

    public function push(mixed $item): void {
        $this->items[] = $item;
        $this->top++;
    }

    public function pop(): mixed {
        if ($this->isEmpty()) return null;
        $item = array_pop($this->items);
        $this->top--;
        return $item;
    }

    public function peek(): mixed {
        if ($this->isEmpty()) return null;
        return $this->items[$this->top];
    }

    public function isEmpty(): bool {
        return $this->top < 0;
    }

    public function size(): int {
        return $this->top + 1;
    }

    public function toArray(): array {
        return $this->items;
    }
}

class MinStack extends Stack {
    private Stack $minStack;

    public function __construct() {
        parent::__construct();
        $this->minStack = new Stack();
    }

    public function push(mixed $item): void {
        parent::push($item);
        if ($this->minStack->isEmpty() || $item <= $this->minStack->peek()) {
            $this->minStack->push($item);
        }
    }

    public function pop(): mixed {
        $item = parent::pop();
        if ($item === $this->minStack->peek()) {
            $this->minStack->pop();
        }
        return $item;
    }

    public function min(): mixed {
        if ($this->minStack->isEmpty()) return null;
        return $this->minStack->peek();
    }
}

$stack = new Stack();
$stack->push(1);
$stack->push(2);
$stack->push(3);
echo $stack->pop() . "\n";
echo $stack->peek() . "\n";
echo $stack->size() . "\n";

$minStack = new MinStack();
$minStack->push(3);
$minStack->push(1);
$minStack->push(2);
$minStack->push(0);
echo $minStack->min() . "\n";
$minStack->pop();
echo $minStack->min() . "\n";
echo "OK\n";
