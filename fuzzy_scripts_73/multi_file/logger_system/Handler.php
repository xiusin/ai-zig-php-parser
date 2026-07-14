<?php
// 日志系统 - 处理器
interface LogHandler {
    public function handle(LogEntry $entry): void;
    public function getEntries(): array;
    public function count(): int;
    public function clear(): void;
}

class MemoryHandler implements LogHandler {
    private array $entries = [];
    private ?int $maxEntries;

    public function __construct(?int $maxEntries = null) {
        $this->maxEntries = $maxEntries;
    }

    public function handle(LogEntry $entry): void {
        $this->entries[] = $entry;
        if ($this->maxEntries !== null && count($this->entries) > $this->maxEntries) {
            array_shift($this->entries);
        }
    }

    public function getEntries(): array {
        return $this->entries;
    }

    public function count(): int {
        return count($this->entries);
    }

    public function clear(): void {
        $this->entries = [];
    }
}

class FilterHandler implements LogHandler {
    private array $entries = [];
    private LogLevel $minLevel;

    public function __construct(LogLevel $minLevel) {
        $this->minLevel = $minLevel;
    }

    public function handle(LogEntry $entry): void {
        if ($entry->level->value >= $this->minLevel->value) {
            $this->entries[] = $entry;
        }
    }

    public function getEntries(): array {
        return $this->entries;
    }

    public function count(): int {
        return count($this->entries);
    }

    public function clear(): void {
        $this->entries = [];
    }
}

class CompositeHandler implements LogHandler {
    private array $handlers = [];
    private array $entries = [];

    public function addHandler(LogHandler $handler): void {
        $this->handlers[] = $handler;
    }

    public function handle(LogEntry $entry): void {
        $this->entries[] = $entry;
        foreach ($this->handlers as $handler) {
            $handler->handle($entry);
        }
    }

    public function getEntries(): array {
        return $this->entries;
    }

    public function count(): int {
        return count($this->entries);
    }

    public function clear(): void {
        $this->entries = [];
        foreach ($this->handlers as $handler) {
            $handler->clear();
        }
    }

    public function getHandlers(): array {
        return $this->handlers;
    }
}
