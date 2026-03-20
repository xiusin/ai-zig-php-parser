<?php
// Test 046: Goto, labels, and control flow
class GotoLab {
    public function process(): string {
        $out = "";

        $x = 0;

        echo "=== Goto example 1 ===\n";
        $counter = 0;
        start:
        $counter++;
        echo "Counter: $counter\n";
        if ($counter < 5) {
            goto start;
        }

        echo "\n=== Goto example 2 ===\n";
        $value = 0;
        for ($i = 0; $i < 10; $i++) {
            if ($i === 5) {
                goto end_loop;
            }
        }
        end_loop:
        echo "Broke at i=5\n";

        echo "\n=== Goto with conditions ===\n";
        $check = false;
        if ($check) {
            goto skip;
        }
        echo "This is executed\n";
        skip:
        echo "Jumped over skip\n";

        echo "\n=== Nested goto ===\n";
        $a = 0;
        outer:
        $a++;
        if ($a > 3) {
            goto done;
        }
        $b = 0;
        inner:
        $b++;
        echo "a=$a, b=$b\n";
        if ($b < 2) {
            goto inner;
        }
        if ($a < 3) {
            goto outer;
        }
        done:
        echo "Done\n";

        return $out;
    }
}

echo "=== Goto Lab ===\n";
$lab = new GotoLab();
echo $lab->process();

echo "\n=== Goto error handling ===\n";
function testGotoError() {
    $error = false;

    if ($error) {
        goto on_error;
    }

    echo "Normal execution\n";

    return;

    on_error:
    echo "Error handler\n";
}

testGotoError();

echo "\n=== Goto in switch ===\n";
$value = 2;
switch ($value) {
    case 1:
        echo "Case 1\n";
        goto end_switch;
    case 2:
        echo "Case 2\n";
        goto case_3;
    case 3:
        case_3:
        echo "Case 3 (or jumped from 2)\n";
        break;
    default:
        echo "Default\n";
}
end_switch:
echo "Switch done\n";

echo "\n=== Goto and loops ===\n";
$found = false;
foreach ([1, 2, 3, 4, 5] as $num) {
    if ($num === 3) {
        $found = true;
        goto found_num;
    }
}
found_num:
echo "Found number or not: " . ($found ? 'yes' : 'no') . "\n";