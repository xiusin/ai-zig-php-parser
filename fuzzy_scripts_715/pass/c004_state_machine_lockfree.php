<?php
// 极度混搭: 状态机 + 锁模拟 + 原子操作模拟 + 线程安全模式 + 异常恢复
echo "=== c004: State Machine + Lock Sim + Atomic + ThreadSafe ===\n\n";

class StateMachine {
    private string $state;
    private array $transitions;
    private array $history = [];
    private bool $locked = false;
    private int $lockHolder = 0;

    public const STATE_IDLE = 'idle';
    public const STATE_RUNNING = 'running';
    public const STATE_PAUSED = 'paused';
    public const STATE_COMPLETED = 'completed';
    public const STATE_FAILED = 'failed';

    public function __construct() {
        $this->state = self::STATE_IDLE;
        $this->transitions = [
            self::STATE_IDLE      => ['start', 'reset'],
            self::STATE_RUNNING  => ['pause', 'stop', 'fail', 'reset'],
            self::STATE_PAUSED   => ['resume', 'stop', 'reset'],
            self::STATE_COMPLETED => ['reset'],
            self::STATE_FAILED    => ['reset', 'retry'],
        ];
    }

    private function acquireLock(int $threadId): bool {
        if ($this->locked && $this->lockHolder !== $threadId) {
            return false;
        }
        $this->locked = true;
        $this->lockHolder = $threadId;
        return true;
    }

    private function releaseLock(int $threadId): void {
        if ($this->lockHolder === $threadId) {
            $this->locked = false;
            $this->lockHolder = 0;
        }
    }

    public function transition(string $action, int $threadId = 1): bool {
        if (!$this->acquireLock($threadId)) {
            echo "  [LOCK FAIL] thread=$threadId state=$this->state\n";
            return false;
        }

        try {
            $allowed = $this->transitions[$this->state] ?? [];
            if (!in_array($action, $allowed)) {
                echo "  [INVALID] state=$this->state action=$action\n";
                return false;
            }

            $oldState = $this->state;
            $this->state = match($action) {
                'start' => self::STATE_RUNNING,
                'pause' => self::STATE_PAUSED,
                'resume' => self::STATE_RUNNING,
                'stop' => self::STATE_COMPLETED,
                'fail' => self::STATE_FAILED,
                'retry' => self::STATE_RUNNING,
                'reset' => self::STATE_IDLE,
                default => $this->state,
            };

            $this->history[] = [
                'thread' => $threadId,
                'action' => $action,
                'from' => $oldState,
                'to' => $this->state,
                'ts' => count($this->history),
            ];

            echo "  [OK] thread=$threadId $oldState ->{$action}-> $this->state\n";
            return true;
        } finally {
            $this->releaseLock($threadId);
        }
    }

    public function getState(): string {
        return $this->state;
    }

    public function getHistory(): array {
        return $this->history;
    }

    public function reset(): void {
        $this->state = self::STATE_IDLE;
        $this->history = [];
        $this->locked = false;
        $this->lockHolder = 0;
    }
}

// === 测试 ===

$sm = new StateMachine();

echo "--- Normal Flow ---\n";
$sm->transition('start', 1);
$sm->transition('pause', 1);
$sm->transition('resume', 1);
$sm->transition('stop', 1);
$sm->transition('reset', 1);

echo "\n--- Error Recovery ---\n";
$sm->transition('start', 1);
$sm->transition('fail', 1);
$sm->transition('retry', 1);
$sm->transition('stop', 1);

echo "\n--- Concurrent Simulation ---\n";
$sm->reset();
$sm->transition('start', 1);
// Thread 2 tries to acquire lock (should fail because thread 1 holds it)
$sm->transition('pause', 2);
// Thread 1 completes
$sm->transition('pause', 1);
$sm->transition('stop', 1);

echo "\n--- Invalid Transitions ---\n";
$sm->transition('start', 1);
$sm->transition('stop', 1);  // OK
$sm->transition('pause', 1); // Invalid from completed
$sm->transition('start', 1); // Invalid from completed
$sm->transition('reset', 1); // OK
$sm->transition('pause', 1); // Invalid from idle

echo "\n--- History ---\n";
$hist = $sm->getHistory();
echo "Total transitions: " . count($hist) . "\n";
foreach ($hist as $h) {
    echo "  #{$h['ts']} thread={$h['thread']} {$h['from']}->{$h['to']} ({$h['action']})\n";
}

echo "\n=== c004 Done ===\n";
