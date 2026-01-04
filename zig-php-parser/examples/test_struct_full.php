<?php
struct Rectangle {
    public int $width;
    public int $height;

    public function __construct($w, $h) {
        $this->width = $w;
        $this->height = $h;
    }

    public function getArea() {
        return $this->width * $this->height;
    }

    public function scale($factor) {
        $this->width = $this->width * $factor;
        $this->height = $this->height * $factor;
    }
}

$r1 = new Rectangle(10, 5);
echo "Initial Area: " . $r1->getArea() . "\n"; // 50

$r1->scale(2);
echo "Scaled Area: " . $r1->getArea() . "\n"; // 200

$r2 = new Rectangle(3, 4);
echo "R2 Area: " . $r2->getArea() . "\n"; // 12
echo "R1 still has height: " . $r1->height . "\n"; // 10
?>
