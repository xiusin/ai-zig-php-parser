<?php
// 测试59: Stringable接口与__toString魔法方法 - PHP 8.0特性
// 测试目的：验证Stringable接口的自动实现和字符串上下文转换

class Money implements Stringable {
    private int $cents;
    private string $currency;
    
    public function __construct(float $amount, string $currency = 'USD') {
        $this->cents = (int)($amount * 100);
        $this->currency = $currency;
    }
    
    public function __toString(): string {
        $amount = $this->cents / 100;
        return sprintf('%s %.2f', $this->currency, $amount);
    }
    
    public function add(Money $other): Money {
        if ($this->currency !== $other->currency) {
            throw new InvalidArgumentException("Currency mismatch");
        }
        $result = new Money(0, $this->currency);
        $result->cents = $this->cents + $other->cents;
        return $result;
    }
}

$price1 = new Money(29.99);
$price2 = new Money(15.50);
$total = $price1->add($price2);

echo "Price 1: $price1\n";
echo "Price 2: $price2\n";
echo "Total: $total\n";

// 自动实现Stringable
class SimpleClass {
    public function __toString(): string {
        return "SimpleClass instance";
    }
}

$simple = new SimpleClass();
echo "Simple: $simple\n";
echo "instanceof Stringable: " . ($simple instanceof Stringable ? 'yes' : 'no') . "\n";

// 字符串上下文中的隐式转换
class Person {
    private string $name;
    private int $age;
    
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function __toString(): string {
        return "{$this->name} ({$this->age} years old)";
    }
}

$person = new Person("Alice", 30);
$description = "User: $person";
echo "$description\n";

// 在sprintf中使用
$formatted = sprintf("Hello, %s!", $person);
echo "$formatted\n";

// 在数组implode中使用（会自动调用__toString）
$items = [new Money(10), new Money(20), new Money(30)];
echo "Items: " . implode(", ", $items) . "\n";

// Stringable类型声明
function formatAsString(Stringable $item): string {
    return "Formatted: " . $item;
}

echo formatAsString(new Money(99.99)) . "\n";
echo formatAsString(new Person("Bob", 25)) . "\n";

// 联合类型中的Stringable
function display(string|Stringable $content): void {
    $str = is_string($content) ? $content : (string)$content;
    echo "Display: $str\n";
}

display("Plain string");
display(new Money(50));

// 可空Stringable
function maybeDisplay(?Stringable $content): void {
    if ($content === null) {
        echo "Nothing to display\n";
    } else {
        echo "Maybe: $content\n";
    }
}

maybeDisplay(null);
maybeDisplay(new Person("Charlie", 35));
?>