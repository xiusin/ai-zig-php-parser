<?php

struct Point {
    public int $x;
    public int $y;
    
    public function __construct(int $x = 0, int $y = 0) {
        $this->x = $x;
        $this->y = $y;
    }
}

$point = new Point(3, 4);
echo "Point created\n";
