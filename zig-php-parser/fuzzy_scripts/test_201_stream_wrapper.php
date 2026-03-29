<?php
class StreamWrapper {
    public $context;
    private $path;
    private $mode;

    public function stream_open(string $path, string $mode, int $options, ?string &$opened_path): bool {
        $this->path = $path;
        $this->mode = $mode;
        $opened_path = $path;
        return true;
    }

    public function stream_read(int $count): string|false {
        return substr($this->path, 0, $count);
    }

    public function stream_eof(): bool {
        return strlen($this->path) === 0;
    }

    public function stream_tell(): int {
        return 0;
    }

    public function stream_seek(int $offset, int $whence): bool {
        return true;
    }
}

stream_register_wrapper("custom", StreamWrapper::class);
$handle = fopen("custom://test/path", "r");
echo get_resource_type($handle) . "\n";
fclose($handle);
echo "OK\n";
