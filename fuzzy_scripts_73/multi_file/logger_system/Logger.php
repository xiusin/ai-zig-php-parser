<?php
// 日志系统 - 日志器主类
class Logger {
    private LogFormatter $formatter;
    private LogHandler $handler;
    private float $startTime;
    private int $logCount = 0;

    public function __construct(LogFormatter $formatter, LogHandler $handler) {
        $this->formatter = $formatter;
        $this->handler = $handler;
        $this->startTime = microtime(true);
    }

    private function elapsed(): float {
        return microtime(true) - $this->startTime;
    }

    public function log(LogLevel $level, string $message, array $context = []): void {
        $entry = new LogEntry($level, $message, $this->elapsed(), $context);
        $this->handler->handle($entry);
        $this->logCount++;
    }

    public function debug(string $message, array $context = []): void {
        $this->log(LogLevel::Debug, $message, $context);
    }

    public function info(string $message, array $context = []): void {
        $this->log(LogLevel::Info, $message, $context);
    }

    public function warning(string $message, array $context = []): void {
        $this->log(LogLevel::Warning, $message, $context);
    }

    public function error(string $message, array $context = []): void {
        $this->log(LogLevel::Error, $message, $context);
    }

    public function critical(string $message, array $context = []): void {
        $this->log(LogLevel::Critical, $message, $context);
    }

    public function getLogCount(): int {
        return $this->logCount;
    }

    public function getHandler(): LogHandler {
        return $this->handler;
    }

    public function setFormatter(LogFormatter $formatter): void {
        $this->formatter = $formatter;
    }

    public function getFormattedEntries(): array {
        return array_map(fn($e) => $this->formatter->format($e), $this->handler->getEntries());
    }

    public function output(): string {
        return implode("\n", $this->getFormattedEntries());
    }
}
