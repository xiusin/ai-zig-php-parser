<?php

// Test 1: Break in loop
echo "Test 1: Break\n";
for ($i = 0; $i < 10; $i = $i + 1) {
    if ($i == 5) {
        break;
    }
    echo $i;
    echo "\n";
}

// Test 2: Continue in loop
echo "Test 2: Continue\n";
for ($i = 0; $i < 5; $i = $i + 1) {
    if ($i == 2) {
        continue;
    }
    echo $i;
    echo "\n";
}

// Test 3: Switch statement
echo "Test 3: Switch\n";
$x = 2;
switch ($x) {
    case 1:
        echo "One\n";
        break;
    case 2:
        echo "Two\n";
        break;
    case 3:
        echo "Three\n";
        break;
    default:
        echo "Other\n";
}

// Test 4: Switch with fall-through
echo "Test 4: Switch fall-through\n";
$y = 1;
switch ($y) {
    case 1:
        echo "A\n";
    case 2:
        echo "B\n";
        break;
    default:
        echo "C\n";
}

// Test 5: Nested loops with break
echo "Test 5: Nested break\n";
for ($i = 0; $i < 3; $i = $i + 1) {
    for ($j = 0; $j < 3; $j = $j + 1) {
        if ($j == 1) {
            break;
        }
        echo $i;
        echo ",";
        echo $j;
        echo "\n";
    }
}
