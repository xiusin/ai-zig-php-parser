<?php
// 测试字符串插值中的属性访问

class Point {
    public int $x;
    public int $y;
    
    public function __construct(int $x, int $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function __toString(): string {
        return "Point($this->x, $this->y)";
    }
}

$p = new Point(10, 20);

// 测试 1: 直接属性访问
echo "X: " . $p->x . "\n";
echo "Y: " . $p->y . "\n";

// 测试 2: 字符串插值中的属性访问
echo "Point: ($p->x, $p->y)\n";

// 测试 3: __toString
echo "ToString: $p\n";

// 测试 4: 复杂表达式
echo "Sum: " . ($p->x + $p->y) . "\n";

echo "All tests passed!\n";
