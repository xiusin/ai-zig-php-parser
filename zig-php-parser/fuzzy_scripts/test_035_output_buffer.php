<?php
// Test 035: Output buffering, ob_* functions
class OutputBufferLab {
    public function process(): string {
        $out = "";

        $out .= "ob_level: " . ob_get_level() . "\n";

        ob_start();
        echo "First buffer content\n";
        $content1 = ob_get_clean();
        $out .= "Content 1: " . trim($content1) . "\n";

        ob_start();
        echo "Second buffer\n";
        echo "More content\n";
        $content2 = ob_get_contents();
        echo " (captured but not cleaned)\n";
        $len = ob_get_length();
        ob_end_clean();
        $out .= "Content 2 length: $len\n";

        ob_start();
        echo "Level: " . ob_get_level() . "\n";
        $levelContent = ob_get_clean();
        $out .= "Level content: " . trim($levelContent) . "\n";

        ob_start();
        ob_start();
        echo "Nested: " . ob_get_level() . "\n";
        ob_end_clean();
        $nestedContent = ob_get_clean();
        $out .= "Nested: " . trim($nestedContent) . "\n";

        ob_start();
        echo "Flush test";
        ob_flush();
        $flushContent = ob_get_clean();
        $out .= "Flush content: " . trim($flushContent) . "\n";

        return $out;
    }

    public function cleanAndFlush(): string {
        $out = "";

        ob_start();
        echo "Line 1\n";
        ob_start();
        echo "Line 2\n";
        ob_start();
        echo "Line 3\n";

        $level = ob_get_level();
        $out .= "Current level: $level\n";

        while (ob_get_level() > 0) {
            ob_end_clean();
        }
        $out .= "After clean all, level: " . ob_get_level() . "\n";

        return $out;
    }
}

echo "=== Output Buffer Lab ===\n";
$lab = new OutputBufferLab();
echo $lab->process();

echo "\n";
echo $lab->cleanAndFlush();

echo "\n=== Output buffering with callbacks ===\n";
ob_start(function($buffer) {
    return strtoupper($buffer);
}, 1024);

echo "this text will be uppercase\n";
echo "more uppercase text\n";

ob_end_flush();

echo "\n=== ob_get_status ===\n";
ob_start();
$status = ob_get_status(true);
echo "Status level: " . $status[0]['level'] . "\n";
echo "Status name: " . $status[0]['name'] . "\n";
ob_end_clean();