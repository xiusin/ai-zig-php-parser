<?php
// 日志系统 - 格式化器
interface LogFormatter {
    public function format(LogEntry $entry): string;
}

class PlainFormatter implements LogFormatter {
    public function format(LogEntry $entry): string {
        $ctx = empty($entry->context) ? '' : ' ' . json_encode($entry->context);
        return sprintf("[%.4f] %s: %s%s", $entry->timestamp, $entry->level->label(), $entry->message, $ctx);
    }
}

class JSONFormatter implements LogFormatter {
    public function format(LogEntry $entry): string {
        return json_encode($entry->toArray());
    }
}

class ColoredFormatter implements LogFormatter {
    public function format(LogEntry $entry): string {
        $color = $entry->level->color();
        $reset = $entry->level->reset();
        $ctx = empty($entry->context) ? '' : ' ' . json_encode($entry->context);
        return sprintf("%s[%.4f] %s: %s%s%s", $color, $entry->timestamp, $entry->level->label(), $entry->message, $ctx, $reset);
    }
}

class CSVFormatter implements LogFormatter {
    public function format(LogEntry $entry): string {
        $ctx = empty($entry->context) ? '' : json_encode($entry->context);
        return sprintf('%.4f,"%s","%s","%s"',
            $entry->timestamp,
            $entry->level->label(),
            str_replace('"', '""', $entry->message),
            str_replace('"', '""', $ctx)
        );
    }
}
