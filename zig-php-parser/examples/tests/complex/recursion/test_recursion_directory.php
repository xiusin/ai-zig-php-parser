<?php
function countFiles($dir, $depth = 0) {
    if ($depth > 3) {
        return 0;
    }
    $count = 0;
    // 模拟目录结构
    $items = ["file1.txt", "file2.txt"];
    if ($depth < 2) {
        $items[] = "subdir1";
        $items[] = "subdir2";
    }
    foreach ($items as $item) {
        $count++;
        if (is_dir($item) && $depth < 2) {
            $count += countFiles($item, $depth + 1);
        }
    }
    return $count;
}

echo "File count: " . countFiles(".") . "\n";
