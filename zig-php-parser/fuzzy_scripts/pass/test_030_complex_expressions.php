<?php
// 测试30: 极度复杂的表达式嵌套
$a = 5;
$b = 10;
$c = 15;
$d = 20;

// 复杂算术表达式
$result1 = (($a + $b) * ($c - $d)) / ($a ?: 1) + ($b ** 2) % $c;
echo "Complex arithmetic: $result1\n";

// 嵌套三元
$result2 = $a > $b ? ($b > $c ? "a>b>c" : ($a > $c ? "a>c>b" : "c>a>b")) : 
           ($a < $c ? ($b < $c ? "c>b>a" : "b>c>a") : "b>a>c");
echo "Nested ternary: $result2\n";

// 赋值链
$x = $y = $z = ($a + $b) * 2;
echo "Assignment chain: x=$x, y=$y, z=$z\n";

// 复合赋值
$val = 10;
$val += $a;
$val -= $b;
$val *= 2;
$val /= 3;
$val %= 7;
echo "Compound assignment: $val\n";

// 位运算组合
$bits = 0b10101010;
$bits = ($bits | 0b00001111) & ~0b00000010;
$bits ^= 0b11110000;
$bits <<= 1;
$bits >>= 2;
echo "Bit operations: " . decbin($bits) . " ($bits)\n";

// 逻辑短路
$count = 0;
$logical = ($count++ > 0) && ($count++ > 1) && ($count++ > 2);
echo "Short-circuit: logical=$logical, count=$count\n";

$count = 0;
$logical2 = ($count++ >= 0) || ($count++ >= 1) || ($count++ >= 2);
echo "Short-circuit OR: logical=$logical2, count=$count\n";

// 字符串拼接表达式
$str = "a" . $a . "b" . $b . "c" . ($c + $d) . "d";
echo "String concat: $str\n";

// 数组访问表达式
$arr = [1 => [2 => [3 => "deep"]]];
$deep = $arr[1][2][3] ?? "not found";
echo "Deep array access: $deep\n";

// 函数调用链
echo "Function chain: " . strtoupper(substr(strrev("hello world"), 0, 5)) . "\n";

// 对象方法链
class Chainable {
    private $value = 0;
    
    public function add($x): self {
        $this->value += $x;
        return $this;
    }
    
    public function mul($x): self {
        $this->value *= $x;
        return $this;
    }
    
    public function sub($x): self {
        $this->value -= $x;
        return $this;
    }
    
    public function get(): int {
        return $this->value;
    }
}

$chainResult = (new Chainable())->add(5)->mul(3)->sub(7)->get();
echo "Method chain: $chainResult\n";

// 错误抑制与表达式
$maybeNull = null;
$safe = @$maybeNull->property ?? "default";
echo "Safe access: $safe\n";
?>
