<?php
// 测试78: 上下文敏感词法分析器 - PHP 7.0+允许保留字作为方法名
class Example {
    // 这些曾经是保留字，现在可以作为方法名
    public function foreach(array $items): void {
        foreach ($items as $item) {
            echo "Item: $item
";
        }
    }
    
    public function if(bool $condition): string {
        if ($condition) {
            return "true";
        }
        return "false";
    }
    
    public function while(int $count): int {
        $sum = 0;
        while ($count > 0) {
            $sum += $count--;
        }
        return $sum;
    }
    
    public function for(int $n): int {
        $result = 1;
        for ($i = 2; $i <= $n; $i++) {
            $result *= $i;
        }
        return $result;
    }
    
    public function switch(string $value): string {
        return match($value) {
            'a' => 'A',
            'b' => 'B',
            default => 'Unknown',
        };
    }
    
    public function class(): string {
        return self::class;
    }
    
    public function echo(string $msg): void {
        echo $msg . "
";
    }
    
    public function print(string $msg): string {
        return "Printed: $msg";
    }
}

$example = new Example();
$example->foreach(['a', 'b', 'c']);
echo "If true: " . $example->if(true) . "
";
echo "While 5: " . $example->while(5) . "
";
echo "For 5: " . $example->for(5) . "
";
echo "Switch 'a': " . $example->switch('a') . "
";
echo "Class: " . $example->class() . "
";
$example->echo("Hello");
echo $example->print("World") . "
";
?>