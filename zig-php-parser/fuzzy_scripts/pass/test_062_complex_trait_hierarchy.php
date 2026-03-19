<?php
// 测试62: 复杂Trait继承层次与冲突解决策略
// 测试目的：验证多层级Trait组合、优先级和修改器

trait Timestampable {
    protected ?DateTime $createdAt = null;
    protected ?DateTime $updatedAt = null;
    
    public function touch(): void {
        $now = new DateTime();
        if ($this->createdAt === null) {
            $this->createdAt = $now;
        }
        $this->updatedAt = $now;
    }
    
    public function getCreatedAt(): ?DateTime {
        return $this->createdAt;
    }
    
    public function getUpdatedAt(): ?DateTime {
        return $this->updatedAt;
    }
}

trait SoftDeletable {
    protected bool $deleted = false;
    protected ?DateTime $deletedAt = null;
    
    public function delete(): void {
        $this->deleted = true;
        $this->deletedAt = new DateTime();
    }
    
    public function restore(): void {
        $this->deleted = false;
        $this->deletedAt = null;
    }
    
    public function isDeleted(): bool {
        return $this->deleted;
    }
}

trait Versionable {
    protected int $version = 1;
    protected array $versionHistory = [];
    
    public function bumpVersion(): void {
        $this->versionHistory[] = [
            'version' => $this->version,
        ];
        $this->version++;
    }
    
    public function getVersion(): int {
        return $this->version;
    }
}

// 冲突解决
trait LoggerTrait {
    protected array $logs = [];
    
    public function log(string $message): void {
        $this->logs[] = [
            'message' => "[LOG] $message",
        ];
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
}

trait VerboseLoggerTrait {
    protected array $verboseLogs = [];
    
    public function log(string $message): void {
        $this->verboseLogs[] = [
            'level' => 'VERBOSE',
            'content' => $message,
        ];
    }
    
    public function getVerboseLogs(): array {
        return $this->verboseLogs;
    }
}

// 使用冲突解决
class Product {
    use Timestampable, SoftDeletable, Versionable;
    use LoggerTrait, VerboseLoggerTrait {
        // 使用LoggerTrait的log方法，但改名为basicLog
        LoggerTrait::log as basicLog;
        // 使用VerboseLoggerTrait的log方法作为主log
        VerboseLoggerTrait::log insteadof LoggerTrait;
    }
    
    private string $name;
    private float $price;
    
    public function __construct(string $name, float $price) {
        $this->name = $name;
        $this->price = $price;
        $this->touch();
        $this->log("Product created: $name");
    }
    
    public function updatePrice(float $newPrice): void {
        $oldPrice = $this->price;
        $this->price = $newPrice;
        $this->touch();
        $this->bumpVersion();
        $this->log("Price changed: $oldPrice -> $newPrice");
    }
    
    public function getInfo(): array {
        return [
            'name' => $this->name,
            'price' => $this->price,
            'version' => $this->getVersion(),
            'deleted' => $this->isDeleted(),
        ];
    }
}

// 测试
$product = new Product("Laptop", 999.99);
echo "Has created timestamp: " . ($product->getCreatedAt() !== null ? 'yes' : 'no') . "\n";
echo "Initial version: " . $product->getVersion() . "\n";

$product->updatePrice(899.99);
$product->updatePrice(799.99);

echo "\nProduct info:\n";
print_r($product->getInfo());

echo "\nLogs (verbose):\n";
print_r($product->getVerboseLogs());

// 软删除
$product->delete();
echo "\nAfter delete - isDeleted: " . ($product->isDeleted() ? 'true' : 'false') . "\n";

$product->restore();
echo "After restore - isDeleted: " . ($product->isDeleted() ? 'true' : 'false') . "\n";

// Trait别名使用
$product->basicLog("This is a basic log entry");
echo "\nBasic logs:\n";
print_r($product->getLogs());

// 多层级Trait组合
trait Auditable {
    use Timestampable;
    
    protected array $auditTrail = [];
    
    public function audit(string $action, array $details = []): void {
        $this->auditTrail[] = [
            'action' => $action,
            'details' => $details,
            'time' => new DateTime(),
        ];
        $this->touch();
    }
    
    public function getAuditTrail(): array {
        return $this->auditTrail;
    }
}

class Order {
    use Auditable, SoftDeletable;
    
    private string $id;
    private string $status = 'pending';
    
    public function __construct() {
        $this->id = uniqid('order_');
        $this->touch();
        $this->audit('order_created', ['id' => $this->id]);
    }
    
    public function ship(): void {
        $this->status = 'shipped';
        $this->audit('order_shipped', ['id' => $this->id]);
    }
}

$order = new Order();
$order->ship();
echo "\nOrder audit trail count: " . count($order->getAuditTrail()) . "\n";
foreach ($order->getAuditTrail() as $entry) {
    echo "- Action: " . $entry['action'] . "\n";
}
?>