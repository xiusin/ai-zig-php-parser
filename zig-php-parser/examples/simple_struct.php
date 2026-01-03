<?php

struct Point {
    public int $x;
    public int $y;
    
    public function __construct(int $x = 0, int $y = 0) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function distance(): float {
        return sqrt($this->x * $this->x + $this->y * $this->y);
    }
}

$point = new Point(3, 4);
echo "Distance: " . $point->distance();