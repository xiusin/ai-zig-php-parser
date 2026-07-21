<?php
// 日志系统
class Logger {
    const DEBUG = 100;
    const INFO = 200;
    const NOTICE = 250;
    const WARNING = 300;
    const ERROR = 400;
    const CRITICAL = 500;
    const ALERT = 550;
    const EMERGENCY = 600;

    private static array $levelNames = [
        100 => 'DEBUG', 200 => 'INFO', 250 => 'NOTICE',
        300 => 'WARNING', 400 => 'ERROR', 500 => 'CRITICAL',
        550 => 'ALERT', 600 => 'EMERGENCY',
    ];

    private array $logs = [];
    private int $minLevel = self::DEBUG;
    private array $handlers = [];

    public function setMinLevel(int $level): self {
        $this->minLevel = $level;
        return $this;
    }

    public function addHandler(callable $handler): self {
        $this->handlers[] = $handler;
        return $this;
    }

    public function log(int $level, string $message, array $context = []): void {
        if ($level < $this->minLevel) return;
        $entry = [
            'level' => $level,
            'level_name' => self::$levelNames[$level] ?? 'UNKNOWN',
            'message' => $message,
            'context' => $context,
            'timestamp' => date('Y-m-d H:i:s'),
        ];
        $this->logs[] = $entry;
        foreach ($this->handlers as $handler) {
            $handler($entry);
        }
    }

    public function debug(string $msg, array $ctx = []): void { $this->log(self::DEBUG, $msg, $ctx); }
    public function info(string $msg, array $ctx = []): void { $this->log(self::INFO, $msg, $ctx); }
    public function notice(string $msg, array $ctx = []): void { $this->log(self::NOTICE, $msg, $ctx); }
    public function warning(string $msg, array $ctx = []): void { $this->log(self::WARNING, $msg, $ctx); }
    public function error(string $msg, array $ctx = []): void { $this->log(self::ERROR, $msg, $ctx); }
    public function critical(string $msg, array $ctx = []): void { $this->log(self::CRITICAL, $msg, $ctx); }

    public function getLogs(): array { return $this->logs; }
    public function getLogsByLevel(int $level): array {
        return array_filter($this->logs, fn($l) => $l['level'] >= $level);
    }
    public function count(): int { return count($this->logs); }
    public function clear(): void { $this->logs = []; }

    public function format(array $entry): string {
        return "[{$entry['timestamp']}] {$entry['level_name']}: {$entry['message']}" .
            (empty($entry['context']) ? '' : ' ' . json_encode($entry['context']));
    }
}
