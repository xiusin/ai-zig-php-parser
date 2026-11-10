<?php
class C { public function cmp($a,$b){return $a<=>$b;} public static function scmp($a,$b){return $a<=>$b;} }
class NC {}
function tryit($label, $fn) { try { $fn(); } catch (TypeError $e) { echo "$label: ", $e->getMessage(), "\n"; } }
$a=[3,1,2]; tryit("strcb", function() use ($a) { usort($a, "nope_fn"); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("int", function() use ($a) { usort($a, 123); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("objno", function() use ($a) { usort($a, new NC); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("arr1", function() use ($a) { usort($a, ["x"]); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("arr_e0", function() use ($a) { usort($a, [[1,2], "m"]); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("cls_nf", function() use ($a) { usort($a, ["NoClass","m"]); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("m_nf", function() use ($a) { usort($a, [new C, "noMethod"]); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("m_nf2", function() use ($a) { usort($a, ["C", "noMethod"]); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("colons", function() use ($a) { usort($a, "C::noMethod"); }); echo json_encode($a), "\n";
$a=[3,1,2]; tryit("e1int", function() use ($a) { usort($a, [new C, 123]); }); echo json_encode($a), "\n";
$a=[3,1,2]; var_dump(usort($a, ["C","scmp"])); echo json_encode($a), "\n";
$a=[3,1,2]; var_dump(usort($a, "usort_cb_ok")); function usort_cb_ok($x,$y){return $x<=>$y;} echo json_encode($a), "\n";
$v="s"; tryit("arg1", function() use ($v) { usort($v, "nope_fn"); });
