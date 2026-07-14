<?php
// 日志系统 - 日志级别枚举
enum LogLevel: int {
    case Debug = 0;
    case Info = 1;
    case Warning = 2;
    case Error = 3;
    case Critical = 4;

    public function label(): string {
        return match($this) {
            LogLevel::Debug => 'DEBUG',
            LogLevel::Info => 'INFO',
            LogLevel::Warning => 'WARNING',
            LogLevel::Error => 'ERROR',
            LogLevel::Critical => 'CRITICAL',
        };
    }

    public function color(): string {
        return match($this) {
            LogLevel::Debug => "\033[37m",    // white
            LogLevel::Info => "\033[32m",     // green
            LogLevel::Warning => "\033[33m",  // yellow
            LogLevel::Error => "\033[31m",    // red
            LogLevel::Critical => "\033[35m", // magenta
        };
    }

    public function reset(): string {
        return "\033[0m";
    }
}

// 日志条目
class LogEntry {
    public function __construct(
        public readonly LogLevel $level,
        public readonly string $message,
        public readonly float $timestamp,
        public readonly array $context = []
    ) {}

    public function toArray(): array {
        return [
            'level' => $this->level->value,
            'level_name' => $this->level->label(),
            'message' => $this->message,
            'timestamp' => $this->timestamp,
            'context' => $this->context,
        ];
    }

    public function __toString(): string {
        $ctx = empty($this->context) ? '' : ' ' . json_encode($this->context);
        return sprintf("[%.4f] %s: %s%s", $this->timestamp, $this->level->label(), $this->message, $ctx);
    }
}
