<?php
// 文件系统模拟：虚拟文件系统、路径操作、目录遍历
echo "=== f160: Virtual FS + Path Ops + Directory Traversal ===\n";

class VirtualFS {
    private array $files = [];
    private array $dirs = [];

    public function __construct() {
        $this->dirs['/'] = [];
    }

    public function mkdir(string $path): bool {
        $path = $this->normalize($path);
        if (isset($this->dirs[$path])) return false;
        $parent = $this->dirname($path);
        if (!isset($this->dirs[$parent])) return false;
        $this->dirs[$path] = [];
        $this->dirs[$parent][] = $this->basename($path);
        return true;
    }

    public function writeFile(string $path, string $content): bool {
        $path = $this->normalize($path);
        $parent = $this->dirname($path);
        if (!isset($this->dirs[$parent])) return false;
        $this->files[$path] = $content;
        if (!in_array($this->basename($path), $this->dirs[$parent])) {
            $this->dirs[$parent][] = $this->basename($path);
        }
        return true;
    }

    public function readFile(string $path): ?string {
        $path = $this->normalize($path);
        return $this->files[$path] ?? null;
    }

    public function deleteFile(string $path): bool {
        $path = $this->normalize($path);
        if (!isset($this->files[$path])) return false;
        unset($this->files[$path]);
        $parent = $this->dirname($path);
        $this->dirs[$parent] = array_values(array_filter(
            $this->dirs[$parent],
            fn($f) => $f !== $this->basename($path)
        ));
        return true;
    }

    public function rmdir(string $path): bool {
        $path = $this->normalize($path);
        if ($path === '/' || !isset($this->dirs[$path])) return false;
        if (!empty($this->dirs[$path])) return false;
        $parent = $this->dirname($path);
        $this->dirs[$parent] = array_values(array_filter(
            $this->dirs[$parent],
            fn($d) => $d !== $this->basename($path)
        ));
        unset($this->dirs[$path]);
        return true;
    }

    public function listDir(string $path): array {
        $path = $this->normalize($path);
        if (!isset($this->dirs[$path])) return [];
        return $this->dirs[$path];
    }

    public function exists(string $path): bool {
        $path = $this->normalize($path);
        return isset($this->files[$path]) || isset($this->dirs[$path]);
    }

    public function isDir(string $path): bool {
        $path = $this->normalize($path);
        return isset($this->dirs[$path]);
    }

    public function isFile(string $path): bool {
        $path = $this->normalize($path);
        return isset($this->files[$path]);
    }

    public function fileSize(string $path): int {
        $path = $this->normalize($path);
        return strlen($this->files[$path] ?? '');
    }

    public function walk(string $path, callable $callback, string $prefix = ''): void {
        $path = $this->normalize($path);
        $entries = $this->listDir($path);
        sort($entries);
        foreach ($entries as $entry) {
            $fullPath = ($path === '/' ? '' : $path) . '/' . $entry;
            $displayPath = $prefix . $entry;
            if ($this->isDir($fullPath)) {
                $callback($displayPath . '/', 'dir', 0);
                $this->walk($fullPath, $callback, $displayPath . '/');
            } else {
                $callback($displayPath, 'file', $this->fileSize($fullPath));
            }
        }
    }

    public function copy(string $src, string $dst): bool {
        $content = $this->readFile($src);
        if ($content === null) return false;
        return $this->writeFile($dst, $content);
    }

    public function move(string $src, string $dst): bool {
        if (!$this->copy($src, $dst)) return false;
        return $this->deleteFile($src);
    }

    public function find(string $path, string $pattern): array {
        $results = [];
        $this->walk($path, function($name, $type, $size) use ($pattern, &$results) {
            if ($type === 'file' && fnmatch($pattern, $name)) {
                $results[] = $name;
            }
        });
        return $results;
    }

    private function normalize(string $path): string {
        $path = str_replace('\\', '/', $path);
        $parts = explode('/', $path);
        $stack = [];
        foreach ($parts as $part) {
            if ($part === '' || $part === '.') continue;
            if ($part === '..') { array_pop($stack); continue; }
            $stack[] = $part;
        }
        return '/' . implode('/', $stack);
    }

    private function dirname(string $path): string {
        $parts = explode('/', $path);
        array_pop($parts);
        return implode('/', $parts) ?: '/';
    }

    private function basename(string $path): string {
        $parts = explode('/', $path);
        return end($parts);
    }
}

// 路径工具
class PathUtils {
    public static function join(string ...$parts): string {
        $result = '';
        foreach ($parts as $part) {
            if ($result === '') {
                $result = $part;
            } else {
                $result = rtrim($result, '/') . '/' . ltrim($part, '/');
            }
        }
        return $result;
    }

    public static function extension(string $path): string {
        $basename = self::basename($path);
        $dotPos = strrpos($basename, '.');
        if ($dotPos === false || $dotPos === 0) return '';
        return substr($basename, $dotPos + 1);
    }

    public static function basename(string $path): string {
        $path = rtrim($path, '/');
        $pos = strrpos($path, '/');
        return $pos === false ? $path : substr($path, $pos + 1);
    }

    public static function dirname(string $path): string {
        $path = rtrim($path, '/');
        $pos = strrpos($path, '/');
        return $pos === false ? '.' : substr($path, 0, $pos);
    }

    public static function split(string $path): array {
        return [
            'dirname' => self::dirname($path),
            'basename' => self::basename($path),
            'extension' => self::extension($path),
            'filename' => self::filename($path),
        ];
    }

    public static function filename(string $path): string {
        $basename = self::basename($path);
        $dotPos = strrpos($basename, '.');
        return $dotPos === false ? $basename : substr($basename, 0, $dotPos);
    }
}

// 测试
echo "--- Virtual File System ---\n";
$fs = new VirtualFS();

// 创建目录结构
$fs->mkdir('/home');
$fs->mkdir('/home/alice');
$fs->mkdir('/home/alice/documents');
$fs->mkdir('/home/alice/downloads');
$fs->mkdir('/home/bob');
$fs->mkdir('/var');
$fs->mkdir('/var/log');
$fs->mkdir('/var/www');
$fs->mkdir('/var/www/public');

// 写文件
$fs->writeFile('/home/alice/documents/readme.txt', 'Welcome to Alice\'s documents!');
$fs->writeFile('/home/alice/documents/notes.md', '# Notes
- Buy groceries
- Call mom
- Finish project');
$fs->writeFile('/home/alice/downloads/file.zip', 'binary data here');
$fs->writeFile('/home/bob/todo.txt', '1. Wake up
2. Code
3. Sleep');
$fs->writeFile('/var/log/app.log', '[2026-07-20 12:00:00] INFO: App started');
$fs->writeFile('/var/log/error.log', '[2026-07-20 12:01:00] ERROR: Something broke');
$fs->writeFile('/var/www/public/index.html', '<html><body><h1>Hello</h1></body></html>');
$fs->writeFile('/var/www/public/style.css', 'body { color: red; }');

echo "  Directory structure:\n";
$fs->walk('/', function($name, $type, $size) {
    if ($type === 'dir') {
        echo "    [DIR]  $name\n";
    } else {
        echo "    [FILE] $name ($size bytes)\n";
    }
});

echo "\n--- File Operations ---\n";
echo "  Read readme.txt: " . substr($fs->readFile('/home/alice/documents/readme.txt'), 0, 30) . "...\n";
echo "  File exists: /home/alice/documents/readme.txt → " . ($fs->exists('/home/alice/documents/readme.txt') ? 'Y' : 'N') . "\n";
echo "  File exists: /nonexistent → " . ($fs->exists('/nonexistent') ? 'Y' : 'N') . "\n";
echo "  Is dir: /home → " . ($fs->isDir('/home') ? 'Y' : 'N') . "\n";
echo "  Is file: /home → " . ($fs->isFile('/home') ? 'Y' : 'N') . "\n";

echo "\n--- Copy and Move ---\n";
$fs->copy('/home/alice/documents/readme.txt', '/home/bob/readme_copy.txt');
echo "  After copy: /home/bob/readme_copy.txt → " . ($fs->exists('/home/bob/readme_copy.txt') ? 'exists' : 'missing') . "\n";
$fs->move('/home/bob/readme_copy.txt', '/home/bob/moved_readme.txt');
echo "  After move: /home/bob/moved_readme.txt → " . ($fs->exists('/home/bob/moved_readme.txt') ? 'exists' : 'missing') . "\n";
echo "  Original copy gone: " . ($fs->exists('/home/bob/readme_copy.txt') ? 'still there' : 'gone') . "\n";

echo "\n--- Find Files ---\n";
echo "  Find *.log in /var/log:\n";
foreach ($fs->find('/var', '*.log') as $file) {
    echo "    $file\n";
}
echo "  Find *.html:\n";
foreach ($fs->find('/', '*.html') as $file) {
    echo "    $file\n";
}

echo "\n--- Path Utilities ---\n";
$paths = [
    '/var/www/public/index.html',
    'documents/notes.md',
    'file.zip',
    '/home/alice/',
    '../parent/child.txt',
];
foreach ($paths as $p) {
    $split = PathUtils::split($p);
    echo "  '$p':\n";
    echo "    dirname: {$split['dirname']}\n";
    echo "    basename: {$split['basename']}\n";
    echo "    filename: {$split['filename']}\n";
    echo "    extension: {$split['extension']}\n";
}

echo "\n--- Path Join ---\n";
echo "  " . PathUtils::join('/var', 'www', 'public') . "\n";
echo "  " . PathUtils::join('home', 'alice', 'documents', 'readme.txt') . "\n";

echo "=== f160 Done ===\n";
