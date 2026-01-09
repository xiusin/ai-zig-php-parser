<?php
function countJsonDepth($data, $depth = 0) {
    if (!is_array($data)) {
        return $depth;
    }
    if (empty($data)) {
        return $depth;
    }
    $max = $depth;
    foreach ($data as $value) {
        $d = countJsonDepth($value, $depth + 1);
        if ($d > $max) {
            $max = $d;
        }
    }
    return $max;
}

$jsonStrings = [
    '{"a": 1}',
    '{"a": {"b": 2}}',
    '{"a": {"b": {"c": {"d": 1}}}}',
    '[1, [2, [3, [4]]]]',
];

foreach ($jsonStrings as $json) {
    $data = json_decode($json, true);
    echo "Depth of $json: " . countJsonDepth($data) . "\n";
}
