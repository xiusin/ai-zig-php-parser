<?php
class Link {
    public $value;
    public $next;

    public function __construct($value, $next = null) {
        $this->value = $value;
        $this->next = $next;
    }
}

function createChain($n) {
    $head = new Link(0);
    $current = $head;
    for ($i = 1; $i < $n; $i++) {
        $current->next = new Link($i);
        $current = $current->next;
    }
    return $head;
}

function sumChain($head) {
    $sum = 0;
    $current = $head;
    while ($current !== null) {
        $sum += $current->value;
        $current = $current->next;
    }
    return $sum;
}

$chain = createChain(100);
echo "Sum of chain: " . sumChain($chain) . "\n";
