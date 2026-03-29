<?php
// 测试34: PHP 8.1枚举测试
enum Status {
    case Draft;
    case Published;
    case Archived;
}

enum Priority: int {
    case Low = 1;
    case Medium = 2;
    case High = 3;
    case Critical = 4;
}

enum Color: string {
    case Red = '#FF0000';
    case Green = '#00FF00';
    case Blue = '#0000FF';
    
    public function getName(): string {
        return match($this) {
            self::Red => '红色',
            self::Green => '绿色',
            self::Blue => '蓝色',
        };
    }
    
    public function isBright(): bool {
        return match($this) {
            self::Red, self::Green => true,
            self::Blue => false,
        };
    }
}

// 基本枚举
$status = Status::Published;
echo "Status: " . $status->name . "\n";

// 有支持值的枚举
$priority = Priority::High;
echo "Priority: " . $priority->name . " = " . $priority->value . "\n";

// 枚举方法
$color = Color::Red;
echo "Color name: " . $color->getName() . "\n";
echo "Is bright: " . ($color->isBright() ? "yes" : "no") . "\n";

// 枚举比较
$status1 = Status::Draft;
$status2 = Status::Draft;
$status3 = Status::Published;
echo "Same enum equal: " . ($status1 === $status2 ? "yes" : "no") . "\n";
echo "Different enum equal: " . ($status1 === $status3 ? "yes" : "no") . "\n";

// 枚举数组
$statuses = Status::cases();
echo "All statuses: ";
foreach ($statuses as $s) {
    echo $s->name . " ";
}
echo "\n";

// 从值创建
$fromValue = Priority::from(2);
echo "From value 2: " . $fromValue->name . "\n";

try {
    $invalid = Priority::from(99);
} catch (ValueError $e) {
    echo "Invalid value error: " . $e->getMessage() . "\n";
}

// tryFrom
$tryResult = Priority::tryFrom(3);
echo "Try from 3: " . ($tryResult?->name ?? "null") . "\n";
$tryResult2 = Priority::tryFrom(99);
echo "Try from 99: " . ($tryResult2?->name ?? "null") . "\n";

// 在switch中使用
function handleStatus(Status $status): string {
    return match($status) {
        Status::Draft => "还在编辑中",
        Status::Published => "已发布",
        Status::Archived => "已归档",
    };
}

echo handleStatus(Status::Published) . "\n";

// 枚举作为数组键
$counts = [
    Status::Draft->name => 5,
    Status::Published->name => 12,
    Status::Archived->name => 3,
];
print_r($counts);
?>
