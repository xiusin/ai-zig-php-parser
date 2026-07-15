<?php
// 极度混搭: 内存文件系统 + 路径解析 + 虚拟目录树 + 遍历 + 元数据
echo "=== c019: VirtualFileSystem + PathResolve + DirTree + Metadata ===\n\n";

class VirtualFile {
    private string $name;
    private bool $isDir;
    private string $content;
    private array $children = [];
    private array $metadata;

    public function __construct(string $name, bool $isDir = false, string $content = '') {
        $this->name = $name;
        $this->isDir = $isDir;
        $this->content = $content;
        $this->metadata = [
            'size' => $isDir ? 0 : strlen($content),
            'created' => 1,
            'modified' => 1,
            'readable' => true,
            'writable' => true,
        ];
    }

    public function getName(): string { return $this->name; }
    public function isDirectory(): bool { return $this->isDir; }
    public function isFile(): bool { return !$this->isDir; }
    public function getContent(): string { return $this->content; }
    public function setContent(string $content): void {
        $this->content = $content;
        $this->metadata['size'] = strlen($content);
        $this->metadata['modified']++;
    }
    public function appendContent(string $content): void {
        $this->content .= $content;
        $this->metadata['size'] = strlen($this->content);
        $this->metadata['modified']++;
    }

    public function addChild(VirtualFile $child): void {
        $this->children[$child->getName()] = $child;
        $this->metadata['modified']++;
    }

    public function getChild(string $name): ?VirtualFile {
        return $this->children[$name] ?? null;
    }

    public function removeChild(string $name): bool {
        if (isset($this->children[$name])) {
            unset($this->children[$name]);
            $this->metadata['modified']++;
            return true;
        }
        return false;
    }

    public function getChildren(): array {
        $list = array_values($this->children);
        usort($list, function($a, $b) {
            if ($a->isDirectory() !== $b->isDirectory()) {
                return $a->isDirectory() ? -1 : 1;
            }
            return strcmp($a->getName(), $b->getName());
        });
        return $list;
    }

    public function getChildCount(): int {
        return count($this->children);
    }

    public function getMetadata(): array {
        return array_merge(['name' => $this->name, 'type' => $this->isDir ? 'dir' : 'file'], $this->metadata);
    }
}

class VirtualFileSystem {
    private VirtualFile $root;
    private string $cwd = '/';

    public function __construct() {
        $this->root = new VirtualFile('/', true);
    }

    public function resolvePath(string $path): string {
        if ($path[0] !== '/') {
            $path = rtrim($this->cwd, '/') . '/' . $path;
        }
        $parts = [];
        foreach (explode('/', $path) as $part) {
            if ($part === '' || $part === '.') continue;
            if ($part === '..') {
                if (!empty($parts)) array_pop($parts);
                continue;
            }
            $parts[] = $part;
        }
        return '/' . implode('/', $parts);
    }

    private function findNode(string $path): ?VirtualFile {
        if ($path === '/') return $this->root;
        $parts = explode('/', trim($path, '/'));
        $current = $this->root;
        foreach ($parts as $part) {
            if (!$current->isDirectory()) return null;
            $child = $current->getChild($part);
            if ($child === null) return null;
            $current = $child;
        }
        return $current;
    }

    public function mkdir(string $path): bool {
        $path = $this->resolvePath($path);
        $parts = explode('/', trim($path, '/'));
        $current = $this->root;
        foreach ($parts as $part) {
            $child = $current->getChild($part);
            if ($child === null) {
                $child = new VirtualFile($part, true);
                $current->addChild($child);
            } elseif (!$child->isDirectory()) {
                return false;
            }
            $current = $child;
        }
        return true;
    }

    public function writeFile(string $path, string $content): bool {
        $path = $this->resolvePath($path);
        $pathParts = explode('/', trim($path, '/'));
        $name = array_pop($pathParts);
        $dir = '/' . implode('/', $pathParts);
        $dirNode = $this->findNode($dir);
        if ($dirNode === null || !$dirNode->isDirectory()) return false;
        $file = $dirNode->getChild($name);
        if ($file === null) {
            $file = new VirtualFile($name, false, $content);
            $dirNode->addChild($file);
        } else {
            $file->setContent($content);
        }
        return true;
    }

    public function readFile(string $path): ?string {
        $path = $this->resolvePath($path);
        $node = $this->findNode($path);
        if ($node === null || !$node->isFile()) return null;
        return $node->getContent();
    }

    public function appendFile(string $path, string $content): bool {
        $path = $this->resolvePath($path);
        $node = $this->findNode($path);
        if ($node === null) return $this->writeFile($path, $content);
        if (!$node->isFile()) return false;
        $node->appendContent($content);
        return true;
    }

    public function delete(string $path): bool {
        $path = $this->resolvePath($path);
        if ($path === '/') return false;
        $pathParts = explode('/', trim($path, '/'));
        $name = array_pop($pathParts);
        $dir = '/' . implode('/', $pathParts);
        $dirNode = $this->findNode($dir);
        if ($dirNode === null) return false;
        return $dirNode->removeChild($name);
    }

    public function listDir(string $path = '/'): array {
        $path = $this->resolvePath($path);
        $node = $this->findNode($path);
        if ($node === null || !$node->isDirectory()) return [];
        return array_map(fn($c) => $c->getName(), $node->getChildren());
    }

    public function getMetadata(string $path): ?array {
        $path = $this->resolvePath($path);
        $node = $this->findNode($path);
        if ($node === null) return null;
        return $node->getMetadata();
    }

    public function tree(string $path = '/', int $maxDepth = 3): void {
        $this->printTree($this->findNode($path), 0, $maxDepth, $path);
    }

    private function printTree(?VirtualFile $node, int $depth, int $maxDepth, string $path): void {
        if ($node === null || $depth > $maxDepth) return;
        $indent = str_repeat('  ', $depth);
        $prefix = $node->isDirectory() ? '[DIR]' : '[FILE:' . $node->getMetadata()['size'] . 'B]';
        echo "$indent$prefix {$node->getName()}\n";
        if ($node->isDirectory()) {
            foreach ($node->getChildren() as $child) {
                $childPath = rtrim($path, '/') . '/' . $child->getName();
                $this->printTree($child, $depth + 1, $maxDepth, $childPath);
            }
        }
    }

    public function chdir(string $path): bool {
        $resolved = $this->resolvePath($path);
        $node = $this->findNode($resolved);
        if ($node === null || !$node->isDirectory()) return false;
        $this->cwd = $resolved;
        return true;
    }

    public function getCwd(): string {
        return $this->cwd;
    }
}

// === 测试 ===

$fs = new VirtualFileSystem();

echo "--- Directory Creation ---\n";
$fs->mkdir('/home/user/documents');
$fs->mkdir('/home/user/downloads');
$fs->mkdir('/home/user/projects/php');
$fs->mkdir('/home/user/projects/zig');
$fs->mkdir('/var/log');
$fs->mkdir('/tmp');

$fs->tree('/');

echo "\n--- File Operations ---\n";
$fs->writeFile('/home/user/documents/readme.txt', 'Hello World!');
$fs->writeFile('/home/user/documents/notes.md', '# Notes\nThis is important.');
$fs->writeFile('/home/user/projects/php/main.php', '<?php echo "Hello";');
$fs->writeFile('/var/log/app.log', 'Application started\n');
$fs->appendFile('/var/log/app.log', 'Application running\n');
$fs->appendFile('/var/log/app.log', 'Application done\n');

echo "readme.txt: " . $fs->readFile('/home/user/documents/readme.txt') . "\n";
echo "app.log:\n" . $fs->readFile('/var/log/app.log') . "\n";

echo "\n--- Relative Path Resolution ---\n";
$fs->chdir('/home/user');
echo "CWD: " . $fs->getCwd() . "\n";
echo "Resolved 'documents/readme.txt': " . $fs->resolvePath('documents/readme.txt') . "\n";
echo "Resolved '../projects': " . $fs->resolvePath('../projects') . "\n";
echo "Resolved '../../var': " . $fs->resolvePath('../../var') . "\n";
echo "Resolved './downloads/../documents': " . $fs->resolvePath('./downloads/../documents') . "\n";

echo "\n--- List Directory ---\n";
$items = $fs->listDir('/home/user');
echo "/home/user: " . implode(", ", $items) . "\n";
$items = $fs->listDir('/home/user/projects');
echo "/home/user/projects: " . implode(", ", $items) . "\n";

echo "\n--- Metadata ---\n";
$meta = $fs->getMetadata('/home/user/documents/readme.txt');
echo "readme.txt meta: " . json_encode($meta) . "\n";
$meta = $fs->getMetadata('/home/user');
echo "/home/user meta: " . json_encode($meta) . "\n";

echo "\n--- Delete ---\n";
$fs->delete('/home/user/documents/notes.md');
echo "After delete, /home/user/documents: " . implode(", ", $fs->listDir('/home/user/documents')) . "\n";

echo "\n--- Directory Tree ---\n";
$fs->tree('/home', 5);

echo "\n=== c019 Done ===\n";
