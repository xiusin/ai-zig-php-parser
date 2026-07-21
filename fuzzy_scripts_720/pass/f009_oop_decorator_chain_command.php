<?php
// 极度混搭: 装饰器链 + 命令模式 + 闭包封装 + 中间件管道 + 异常回滚
echo "=== f009: Decorator Chain + Command Pattern + Middleware ===\n";

interface Command {
    public function execute(array $context): array;
    public function undo(array $context): array;
}

class CreateCommand implements Command {
    public function execute(array $context): array {
        $context['created'] = true;
        $context['log'][] = "created item {$context['id']}";
        return $context;
    }
    public function undo(array $context): array {
        $context['created'] = false;
        $context['log'][] = "undid create item {$context['id']}";
        return $context;
    }
}

class UpdateCommand implements Command {
    private mixed $oldValue = null;

    public function execute(array $context): array {
        $this->oldValue = $context['value'] ?? null;
        $context['value'] = $context['newValue'] ?? 'updated';
        $context['log'][] = "updated item {$context['id']}: {$this->oldValue} -> {$context['value']}";
        return $context;
    }
    public function undo(array $context): array {
        $context['value'] = $this->oldValue;
        $context['log'][] = "undid update item {$context['id']}: reverted to {$this->oldValue}";
        return $context;
    }
}

class DeleteCommand implements Command {
    public function execute(array $context): array {
        $context['deleted'] = true;
        $context['log'][] = "deleted item {$context['id']}";
        return $context;
    }
    public function undo(array $context): array {
        $context['deleted'] = false;
        $context['log'][] = "undid delete item {$context['id']}";
        return $context;
    }
}

// 装饰器：日志、缓存、验证、事务
abstract class CommandDecorator implements Command {
    protected Command $wrapped;

    public function __construct(Command $command) {
        $this->wrapped = $command;
    }

    public function execute(array $context): array {
        return $this->wrapped->execute($context);
    }

    public function undo(array $context): array {
        return $this->wrapped->undo($context);
    }
}

class LoggingDecorator extends CommandDecorator {
    public function execute(array $context): array {
        $context['log'][] = "[LOG] Before execute " . get_class($this->wrapped);
        $context = parent::execute($context);
        $context['log'][] = "[LOG] After execute " . get_class($this->wrapped);
        return $context;
    }
    public function undo(array $context): array {
        $context['log'][] = "[LOG] Before undo " . get_class($this->wrapped);
        $context = parent::undo($context);
        $context['log'][] = "[LOG] After undo " . get_class($this->wrapped);
        return $context;
    }
}

class ValidationDecorator extends CommandDecorator {
    public function execute(array $context): array {
        if (!isset($context['id'])) {
            throw new InvalidArgumentException("Context missing 'id'");
        }
        $context['log'][] = "[VALIDATE] id={$context['id']} OK";
        return parent::execute($context);
    }
}

class TransactionDecorator extends CommandDecorator {
    public function execute(array $context): array {
        $context['log'][] = "[TX] BEGIN";
        try {
            $context = parent::execute($context);
            $context['log'][] = "[TX] COMMIT";
            return $context;
        } catch (\Throwable $e) {
            $context['log'][] = "[TX] ROLLBACK: " . $e->getMessage();
            throw $e;
        }
    }
}

// 命令调用器（支持撤销栈）
class CommandInvoker {
    private array $undoStack = [];
    private array $redoStack = [];

    public function execute(Command $command, array $context): array {
        $context = $command->execute($context);
        $this->undoStack[] = $command;
        $this->redoStack = []; // 清空重做栈
        return $context;
    }

    public function undo(array $context): array {
        if (empty($this->undoStack)) {
            $context['log'][] = "[INVOKER] Nothing to undo";
            return $context;
        }
        $command = array_pop($this->undoStack);
        $context = $command->undo($context);
        $this->redoStack[] = $command;
        return $context;
    }

    public function redo(array $context): array {
        if (empty($this->redoStack)) {
            $context['log'][] = "[INVOKER] Nothing to redo";
            return $context;
        }
        $command = array_pop($this->redoStack);
        $context = $command->execute($context);
        $this->undoStack[] = $command;
        return $context;
    }
}

// === 测试 ===
$invoker = new CommandInvoker();
$context = ['id' => 'ITEM-001', 'log' => []];

// 创建命令（带装饰器）
$createCommand = new TransactionDecorator(
    new LoggingDecorator(
        new ValidationDecorator(
            new CreateCommand()
        )
    )
);

$context = $invoker->execute($createCommand, $context);
echo "After create: created=" . var_export($context['created'] ?? false, true) . "\n";

// 更新命令
$updateCommand = new LoggingDecorator(
    new ValidationDecorator(
        new UpdateCommand()
    )
);
$context['newValue'] = 'new_value';
$context = $invoker->execute($updateCommand, $context);
echo "After update: value={$context['value']}\n";

// 删除命令
$deleteCommand = new LoggingDecorator(new DeleteCommand());
$context = $invoker->execute($deleteCommand, $context);
echo "After delete: deleted=" . var_export($context['deleted'] ?? false, true) . "\n";

// 撤销
echo "\n--- Undo ---\n";
$context = $invoker->undo($context);
echo "After undo delete: deleted=" . var_export($context['deleted'] ?? false, true) . "\n";

$context = $invoker->undo($context);
echo "After undo update: value={$context['value']}\n";

// 重做
echo "\n--- Redo ---\n";
$context = $invoker->redo($context);
echo "After redo update: value={$context['value']}\n";

// 异常测试（验证失败）
echo "\n--- Exception Test ---\n";
$badCommand = new ValidationDecorator(new CreateCommand());
try {
    $badContext = ['log' => []]; // 缺少 id
    $badContext = $badCommand->execute($badContext);
} catch (InvalidArgumentException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// 打印日志
echo "\n--- Log ---\n";
foreach ($context['log'] as $entry) {
    echo "  $entry\n";
}

echo "=== f009 Done ===\n";
