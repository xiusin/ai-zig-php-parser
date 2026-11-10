<?php
function t($label, $v) {
    try { $r = sort($v); echo "$label: r=", var_export($r, true), "\n"; }
    catch (TypeError $e) { echo "$label caught: ", $e->getMessage(), "\n"; }
    var_dump($v);
}
t("str", "str");
t("int", 123);
t("float", 1.5);
t("null", null);
t("true", true);
class P {}
t("obj", new P);
$a = [3, 1, 2];
var_dump(sort($a));
echo json_encode($a), "\n";
foreach (["rsort","asort","arsort","ksort","krsort"] as $fn) {
    $v = "s";
    try { $fn($v); } catch (TypeError $e) { echo "$fn caught: ", $e->getMessage(), "\n"; }
}
