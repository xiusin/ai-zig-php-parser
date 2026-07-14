<?php
// 电商系统 - 订单
enum OrderStatus: string {
    case Pending = 'pending';
    case Confirmed = 'confirmed';
    case Shipped = 'shipped';
    case Delivered = 'delivered';
    case Cancelled = 'cancelled';

    public function label(): string {
        return match($this) {
            OrderStatus::Pending => '待处理',
            OrderStatus::Confirmed => '已确认',
            OrderStatus::Shipped => '已发货',
            OrderStatus::Delivered => '已送达',
            OrderStatus::Cancelled => '已取消',
        };
    }

    public function canTransitionTo(OrderStatus $next): bool {
        return match($this) {
            OrderStatus::Pending => in_array($next, [OrderStatus::Confirmed, OrderStatus::Cancelled]),
            OrderStatus::Confirmed => in_array($next, [OrderStatus::Shipped, OrderStatus::Cancelled]),
            OrderStatus::Shipped => $next === OrderStatus::Delivered,
            OrderStatus::Delivered => false,
            OrderStatus::Cancelled => false,
        };
    }
}

class Order {
    private static int $nextId = 1001;

    public readonly int $id;
    public OrderStatus $status;
    private array $items;
    private float $total;
    private string $createdAt;

    public function __construct(
        Cart $cart,
        private ?User $user = null
    ) {
        $this->id = self::$nextId++;
        $this->status = OrderStatus::Pending;
        $this->items = $cart->getItems();
        $this->total = $cart->total();
        $this->createdAt = date('Y-m-d H:i:s');
    }

    public function confirm(): bool {
        if ($this->status->canTransitionTo(OrderStatus::Confirmed)) {
            $this->status = OrderStatus::Confirmed;
            return true;
        }
        return false;
    }

    public function ship(): bool {
        if ($this->status->canTransitionTo(OrderStatus::Shipped)) {
            $this->status = OrderStatus::Shipped;
            return true;
        }
        return false;
    }

    public function deliver(): bool {
        if ($this->status->canTransitionTo(OrderStatus::Delivered)) {
            $this->status = OrderStatus::Delivered;
            return true;
        }
        return false;
    }

    public function cancel(): bool {
        if ($this->status->canTransitionTo(OrderStatus::Cancelled)) {
            $this->status = OrderStatus::Cancelled;
            return true;
        }
        return false;
    }

    public function getTotal(): float {
        return $this->total;
    }

    public function getItems(): array {
        return $this->items;
    }

    public function getItemCount(): int {
        return count($this->items);
    }

    public function display(): string {
        $lines = [
            "=== Order #{$this->id} ===",
            "Status: " . $this->status->label() . " ({$this->status->value})",
            "Created: {$this->createdAt}",
            "Items:",
        ];
        foreach ($this->items as $item) {
            $lines[] = "  $item";
        }
        $lines[] = sprintf("Total: $%.2f", $this->total);
        return implode("\n", $lines);
    }
}
