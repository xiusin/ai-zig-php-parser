<?php
function parseIni(string $ini): array {
    $result = [];
    $currentSection = '';
    $lines = explode("\n", $ini);

    foreach ($lines as $line) {
        $line = trim($line);
        if (empty($line) || $line[0] === ';') continue;

        if ($line[0] === '[' && substr($line, -1) === ']') {
            $currentSection = substr($line, 1, -1);
            $result[$currentSection] = [];
            continue;
        }

        if (str_contains($line, '=')) {
            [$key, $value] = explode('=', $line, 2);
            $key = trim($key);
            $value = trim($value);

            if (preg_match('/^"(.*)"$/', $value, $m)) {
                $value = $m[1];
            } elseif (preg_match("/^'(.*)'$/", $value, $m)) {
                $value = $m[1];
            }

            if ($currentSection) {
                $result[$currentSection][$key] = $value;
            } else {
                $result[$key] = $value;
            }
        }
    }

    return $result;
}

$ini = "; Database configuration
[database]
host = \"localhost\"
port = 3306
name = 'testdb'

[cache]
enabled = true
ttl = 3600
";

$result = parseIni($ini);
echo $result['database']['host'] . "\n";
echo $result['database']['port'] . "\n";
echo $result['cache']['enabled'] . "\n";
echo "OK\n";
