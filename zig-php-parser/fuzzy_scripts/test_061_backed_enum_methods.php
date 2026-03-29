<?php
// 测试61: 有值枚举(Backed Enum)的高级用法 - 方法、接口实现、序列化
// 测试目的：验证Backed Enum的完整功能集

interface Labelable {
    public function label(): string;
}

enum Status: int implements Labelable, Stringable {
    case Draft = 0;
    case Pending = 1;
    case Approved = 2;
    case Rejected = 3;
    case Published = 4;
    case Archived = 5;
    
    public function label(): string {
        return match($this) {
            self::Draft => '草稿',
            self::Pending => '待审核',
            self::Approved => '已通过',
            self::Rejected => '已拒绝',
            self::Published => '已发布',
            self::Archived => '已归档',
        };
    }
    
    public function __toString(): string {
        return $this->name;
    }
    
    public function color(): string {
        return match($this) {
            self::Draft => '#999',
            self::Pending => '#f90',
            self::Approved => '#0c0',
            self::Rejected => '#c00',
            self::Published => '#00c',
            self::Archived => '#666',
        };
    }
    
    public function canTransitionTo(self $newStatus): bool {
        return match($this) {
            self::Draft => in_array($newStatus, [self::Pending, self::Archived]),
            self::Pending => in_array($newStatus, [self::Approved, self::Rejected]),
            self::Approved => in_array($newStatus, [self::Published, self::Archived]),
            self::Rejected => in_array($newStatus, [self::Draft, self::Archived]),
            self::Published => in_array($newStatus, [self::Archived]),
            self::Archived => false,
        };
    }
}

// 使用枚举
$current = Status::Draft;
echo "Current status: {$current->label()} ({$current->value})\n";
echo "Color: {$current->color()}\n";

// 转换
$transitions = [Status::Pending, Status::Approved, Status::Published];
foreach ($transitions as $next) {
    $can = $current->canTransitionTo($next) ? '✓' : '✗';
    echo "  $can {$current->label()} → {$next->label()}\n";
}

// 从值创建
$value = 2;
try {
    $fromValue = Status::from($value);
    echo "\nFrom value $value: {$fromValue->label()}\n";
} catch (ValueError $e) {
    echo "Invalid value: $value\n";
}

// 安全创建
$safeStatus = Status::tryFrom(99);
echo "Try from 99: " . ($safeStatus === null ? 'null' : $safeStatus->label()) . "\n";

$safeStatus2 = Status::tryFrom(4);
echo "Try from 4: " . ($safeStatus2?->label() ?? 'null') . "\n";

// 字符串枚举
enum Permission: string {
    case Read = 'read';
    case Write = 'write';
    case Delete = 'delete';
    case Admin = 'admin';
    
    public function level(): int {
        return match($this) {
            self::Read => 1,
            self::Write => 2,
            self::Delete => 3,
            self::Admin => 4,
        };
    }
}

$perm = Permission::Write;
echo "\nPermission: {$perm->value}, level: {$perm->level()}\n";

// 枚举序列化
$serialized = serialize(Status::Published);
$unserialized = unserialize($serialized);
echo "\nSerialized and back: {$unserialized->label()}\n";
echo "Same instance: " . (Status::Published === $unserialized ? 'yes' : 'no') . "\n";

// 在数组中使用
$allStatuses = Status::cases();
echo "\nAll statuses:\n";
foreach ($allStatuses as $status) {
    echo "  {$status->value}: {$status->label()}\n";
}

// 过滤
$activeStatuses = array_filter($allStatuses, fn($s) => $s->value >= 2);
echo "\nActive statuses (value >= 2): " . count($activeStatuses) . "\n";
?>
