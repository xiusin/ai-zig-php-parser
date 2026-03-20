<?php
// Test 120: Enums with methods and interfaces
interface Labeled {
    public function getLabel(): string;
}

enum StatusEnum implements Labeled {
    case Active;
    case Inactive;
    case Pending;

    public function getLabel(): string {
        return match($this) {
            self::Active => 'Active',
            self::Inactive => 'Inactive',
            self::Pending => 'Pending',
        };
    }

    public function isActive(): bool {
        return $this === self::Active;
    }
}

echo "=== Enum implementing interface ===\n";
$status = StatusEnum::Active;
echo "status->getLabel(): " . $status->getLabel() . "\n";
echo "status->isActive(): " . ($status->isActive() ? 'true' : 'false') . "\n";

echo "\n=== Enum method ===\n";
$inactive = StatusEnum::Inactive;
echo "inactive->isActive(): " . ($inactive->isActive() ? 'true' : 'false') . "\n";

echo "\n=== All cases ===\n";
foreach (StatusEnum::cases() as $case) {
    echo "  {$case->name}: {$case->getLabel()}\n";
}