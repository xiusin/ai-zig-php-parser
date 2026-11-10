<?php
function t($label, $fn) { try { $r = $fn(); echo "$label: ", var_export($r, true), "\n"; } catch (Error $e) { echo "$label caught ", get_class($e), ": ", $e->getMessage(), "\n"; } }
$a=[3,1,2]; $b=[1,2]; t("incons", function() use (&$a,&$b) { return array_multisort($a, $b); }); echo json_encode($a)," ",json_encode($b),"\n";
$a=[3,1,2]; $b="x"; t("nonarray2", function() use (&$a,&$b) { return array_multisort($a, $b); }); echo json_encode($a)," ",var_export($b,true),"\n";
$a=[3,1,2]; $b=[1,2,3]; t("badflag", function() use (&$a,&$b) { return array_multisort($a, 999, $b); }); echo json_encode($a)," ",json_encode($b),"\n";
t("str1", function() { return array_multisort("x"); });
t("int1", function() { return array_multisort(4); });
t("int1bad", function() { return array_multisort(999); });
$a=[2,1]; t("flag7", function() use (&$a) { return array_multisort($a, 7); }); echo json_encode($a),"\n";
$a=[2,1]; t("flag11", function() use (&$a) { return array_multisort($a, 11); }); echo json_encode($a),"\n";
$a=[3,1,2]; $b=[9,8,7]; t("desc", function() use (&$a,&$b) { return array_multisort($a, SORT_DESC, $b); }); echo json_encode($a)," ",json_encode($b),"\n";
$a=[3,1,2]; t("plain", function() use (&$a) { return array_multisort($a); }); echo json_encode($a),"\n";
