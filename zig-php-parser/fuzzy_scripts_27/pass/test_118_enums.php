<?php
// Test 118: Enums (backed enums)
enum Status: string {
    case Active = 'active';
    case Inactive = 'inactive';
    case Pending = 'pending';

    public function label(): string {
        return match($this) {
            self::Active => 'Active Status',
            self::Inactive => 'Inactive Status',
            self::Pending => 'Pending Status',
        };
    }

    public function isActive(): bool {
        return $this === self::Active;
    }
}

enum Priority: int {
    case Low = 1;
    case Medium = 2;
    case High = 3;
}

echo "=== Backed string enum ===\n";
echo "Status::Active->value: " . Status::Active->value . "\n";
echo "Status::Active->label(): " . Status::Active->label() . "\n";
echo "Status::Active->isActive(): " . (Status::Active->isActive() ? 'true' : 'false') . "\n";
echo "Status::Inactive->isActive(): " . (Status::Inactive->isActive() ? 'true' : 'false') . "\n";

echo "\n=== Backed int enum ===\n";
echo "Priority::Low->value: " . Priority::Low->value . "\n";
echo "Priority::High->value: " . Priority::High->value . "\n";

echo "\n=== Enum cases ===\n";
echo "Status cases:\n";
foreach (Status::cases() as $case) {
    echo "  {$case->name} = {$case->value}\n";
}

echo "\n=== Enum from ===\n";
$parsed = Status::from('active');
echo "Status::from('active'): " . ($parsed ? $parsed->label() : 'null') . "\n";

try {
    $invalid = Status::from('invalid');
} catch (ValueError $e) {
    echo "ValueError for invalid: caught\n";
}

$try = Status::tryFrom('inactive');
echo "Status::tryFrom('inactive'): " . ($try ? $try->label() : 'null') . "\n";