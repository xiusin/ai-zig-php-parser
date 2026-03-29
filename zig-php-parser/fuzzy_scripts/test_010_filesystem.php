<?php
// Test 010: File operations, directory, and filesystem
class FileLab {
    private string $testDir;
    private string $testFile;

    public function __construct() {
        $this->testDir = sys_get_temp_dir() . '/php_test_' . getmypid();
        mkdir($this->testDir, 0755, true);
        $this->testFile = $this->testDir . '/test.txt';
    }

    public function __destruct() {
        $this->cleanup();
    }

    public function process(): string {
        $out = "";

        // File write/read
        $content = "Hello, World!\nLine 2\nLine 3\n中文测试";
        file_put_contents($this->testFile, $content);
        $out .= "Wrote " . strlen($content) . " bytes\n";

        $read = file_get_contents($this->testFile);
        $out .= "Read: " . strlen($read) . " bytes\n";
        $out .= "Content match: " . ($read === $content ? 'yes' : 'no') . "\n";

        // File exists
        $out .= "File exists: " . (file_exists($this->testFile) ? 'yes' : 'no') . "\n";
        $out .= "Is file: " . (is_file($this->testFile) ? 'yes' : 'no') . "\n";
        $out .= "Is dir: " . (is_dir($this->testFile) ? 'yes' : 'no') . "\n";

        // File info
        $out .= "File size: " . filesize($this->testFile) . "\n";
        $out .= "File mtime: " . filemtime($this->testFile) . "\n";
        $out .= "File atime: " . fileatime($this->testFile) . "\n";
        $out .= "Basename: " . basename($this->testFile) . "\n";
        $out .= "Dirname: " . dirname($this->testFile) . "\n";

        // Read lines
        $lines = file($this->testFile);
        $out .= "Lines count: " . count($lines) . "\n";

        // Directory operations
        $subdir = $this->testDir . '/subdir';
        mkdir($subdir, 0755);
        $out .= "Created subdir: " . (is_dir($subdir) ? 'yes' : 'no') . "\n";

        // Glob
        $files = glob($this->testDir . '/*');
        $out .= "Glob files: " . count($files) . "\n";

        // Copy
        $copyFile = $this->testDir . '/copy.txt';
        copy($this->testFile, $copyFile);
        $out .= "Copy exists: " . (file_exists($copyFile) ? 'yes' : 'no') . "\n";

        // Rename
        $renamedFile = $this->testDir . '/renamed.txt';
        rename($copyFile, $renamedFile);
        $out .= "Rename exists: " . (file_exists($renamedFile) ? 'yes' : 'no') . "\n";
        $out .= "Original copy gone: " . (!file_exists($copyFile) ? 'yes' : 'no') . "\n";

        // Touch
        $newFile = $this->testDir . '/new.txt';
        touch($newFile);
        $out .= "Touch created: " . (file_exists($newFile) ? 'yes' : 'no') . "\n";

        // Temp files
        $tmp = tempnam($this->testDir, 'tmp');
        $out .= "Temp file: " . basename($tmp) . "\n";

        return $out;
    }

    public function pathFunctions(): string {
        $out = "";

        // Path info
        $path = '/home/user/docs/file.txt';
        $info = pathinfo($path);
        $out .= "Pathinfo dirname: " . ($info['dirname'] ?? 'n/a') . "\n";
        $out .= "Pathinfo basename: " . ($info['basename'] ?? 'n/a') . "\n";
        $out .= "Pathinfo extension: " . ($info['extension'] ?? 'n/a') . "\n";
        $out .= "Pathinfo filename: " . ($info['filename'] ?? 'n/a') . "\n";

        // Realpath
        $real = realpath($this->testFile);
        $out .= "Realpath: " . ($real ?: 'null') . "\n";

        // Path join
        $joined = $this->testDir . DIRECTORY_SEPARATOR . 'subdir' . DIRECTORY_SEPARATOR . 'file.txt';
        $out .= "Joined path: " . $joined . "\n";

        return $out;
    }

    private function cleanup(): void {
        if (is_dir($this->testDir)) {
            $files = glob($this->testDir . '/*');
            foreach ($files as $file) {
                unlink($file);
            }
            rmdir($this->testDir);
        }
    }
}

$lab = new FileLab();
echo $lab->process();
echo "\n";
echo $lab->pathFunctions();