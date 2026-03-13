<?php
// 接口测试 2
interface Shape {
    public function area();
}
class Rectangle2 implements Shape {
    private $w;
    private $h;
    public function __construct($w, $h) { $this->w = $w; $this->h = $h; }
    public function area() { return $this->w * $this->h; }
}
$rect = new Rectangle2(8, 8);
echo $rect->area();
echo "
";
?>