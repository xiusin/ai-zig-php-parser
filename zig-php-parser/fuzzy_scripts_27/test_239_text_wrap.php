<?php
function wrapText(string $text, int $width): string {
    $words = explode(' ', $text);
    $lines = [];
    $currentLine = '';
    $currentLength = 0;

    foreach ($words as $word) {
        $wordLength = strlen($word);

        if ($currentLength + $wordLength + ($currentLine !== '' ? 1 : 0) > $width) {
            if ($currentLine !== '') {
                $lines[] = $currentLine;
            }
            $currentLine = $word;
            $currentLength = $wordLength;
        } else {
            if ($currentLine !== '') {
                $currentLine .= ' ';
                $currentLength++;
            }
            $currentLine .= $word;
            $currentLength += $wordLength;
        }
    }

    if ($currentLine !== '') {
        $lines[] = $currentLine;
    }

    return implode("\n", $lines);
}

function countWords(string $text): int {
    return count(preg_split('/\s+/', trim($text)));
}

function truncateWords(string $text, int $limit, string $suffix = '...'): string {
    $words = preg_split('/\s+/', trim($text));
    if (count($words) <= $limit) return $text;
    return implode(' ', array_slice($words, 0, $limit)) . $suffix;
}

$text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore.";
echo wrapText($text, 20) . "\n";
echo "Word count: " . countWords($text) . "\n";
echo truncateWords($text, 8) . "\n";
echo "OK\n";
