<?php
// 极度混搭: 枚举(带方法/实现接口) + match表达式 + 多态分派 + 状态机 + 闭包策略
echo "=== f003: Enum + Match + State Machine + Strategy ===\n";

enum OrderStatus: string implements \UnitEnum {
    case Pending = 'pending';
    case Processing = 'processing';
    case Shipped = 'shipped';
    case Delivered = 'delivered';
    case Cancelled = 'cancelled';

    public function label(): string {
        return match($this) {
            self::Pending => '待处理',
            self::Processing => '处理中',
            self::Shipped => '已发货',
            self::Delivered => '已送达',
            self::Cancelled => '已取消',
        };
    }

    public function canTransitionTo(self $next): bool {
        return match([$this, $next]) {
            [self::Pending, self::Processing] => true,
            [self::Processing, self::Shipped] => true,
            [self::Shipped, self::Delivered] => true,
            [self::Pending, self::Cancelled] => true,
            [self::Processing, self::Cancelled] => true,
            default => false,
        };
    }

    public function isFinal(): bool {
        return match($this) {
            self::Delivered, self::Cancelled => true,
            default => false,
        };
    }

    public function color(): string {
        return match($this) {
            self::Pending => 'yellow',
            self::Processing => 'blue',
            self::Shipped => 'cyan',
            self::Delivered => 'green',
            self::Cancelled => 'red',
        };
    }
}

class Order {
    private OrderStatus $status;
    private array $history = [];

    public function __construct(
        public readonly string $id,
        public readonly float $amount
    ) {
        $this->status = OrderStatus::Pending;
        $this->history[] = ['status' => $this->status, 'action' => 'created'];
    }

    public function getStatus(): OrderStatus { return $this->status; }

    public function transition(OrderStatus $next, string $reason = ''): bool {
        if (!$this->status->canTransitionTo($next)) {
            echo "  Cannot transition from {$this->status->label()} to {$next->label()}\n";
            return false;
        }
        $this->status = $next;
        $this->history[] = ['status' => $next, 'action' => $reason];
        return true;
    }

    public function getHistory(): array { return $this->history; }

    public function process(callable $strategy): string {
        return $strategy($this);
    }
}

// 策略模式 via 闭包
$expressStrategy = fn(Order $o) => sprintf("Express: %s $%.2f", $o->id, $o->amount * 1.5);
$standardStrategy = fn(Order $o) => sprintf("Standard: %s $%.2f", $o->id, $o->amount);
$economyStrategy = function(Order $o) {
    $discount = $o->amount > 100 ? 0.1 : 0.05;
    return sprintf("Economy: %s $%.2f (discount %.0f%%)", $o->id, $o->amount * (1 - $discount), $discount * 100);
};

// 测试订单流转
$order = new Order("ORD-001", 150.00);
echo "Initial: {$order->getStatus()->label()} ({$order->getStatus()->color()})\n";

$order->transition(OrderStatus::Processing, "payment confirmed");
echo "After processing: {$order->getStatus()->label()}\n";

$order->transition(OrderStatus::Shipped, "carrier picked up");
echo "After shipping: {$order->getStatus()->label()}\n";

// 非法转换
$order->transition(OrderStatus::Pending, "trying to go back");
$order->transition(OrderStatus::Delivered, "out for delivery");

$order->transition(OrderStatus::Delivered, "customer received");
echo "Final: {$order->getStatus()->label()} isFinal=" . var_export($order->getStatus()->isFinal(), true) . "\n";

// 历史记录
echo "\nOrder history:\n";
foreach ($order->getHistory() as $h) {
    echo "  {$h['status']->label()}: {$h['action']}\n";
}

// 策略处理
$order2 = new Order("ORD-002", 80.00);
echo "\n" . $order2->process($expressStrategy) . "\n";
echo $order2->process($standardStrategy) . "\n";
echo $order2->process($economyStrategy) . "\n";

$order3 = new Order("ORD-003", 200.00);
echo $order3->process($economyStrategy) . "\n";

// 枚举遍历
echo "\nAll statuses:\n";
foreach (OrderStatus::cases() as $status) {
    echo "  {$status->name} = '{$status->value}' => {$status->label()} [{$status->color()}] final=" . var_export($status->isFinal(), true) . "\n";
}

echo "=== f003 Done ===\n";
