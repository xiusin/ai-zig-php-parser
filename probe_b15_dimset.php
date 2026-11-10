<?php
// ① 字符串 alloca 直参（顶层）
$s1 = "abc";
$s1[0] = "Z";
echo "top-str: $s1\n";
// ② 字符串函数内局部（alloca load 临时）
function f_local() {
    $s = "xyz";
    $s[2] = "Q";
    echo "local-str: $s\n";
}
f_local();
// ③ 字符串引用形参（分支①）
function f_ref(&$s) { $s[1] = "M"; }
$s3 = "dog";
f_ref($s3);
echo "ref-str: $s3\n";
// ④ 数组字面量构建（test_065 原路径）
$arr = ['a' => 1, 'b' => 2, 'c' => 3];
echo "lit: ", json_encode($arr), "\n";
// ⑤ 数组 dim-set（alloca 直参与 load 临时）
$a = [1, 2, 3];
$a[1] = 99;
echo "arr: ", json_encode($a), "\n";
function f_arr() {
    $b = ['x', 'y'];
    $b[] = 'z';
    echo "f-arr: ", json_encode($b), "\n";
}
f_arr();
// ⑥ 对象 ArrayAccess offsetSet
class C implements ArrayAccess {
    public array $d = [];
    public function offsetExists(mixed $o): bool { return isset($this->d[$o]); }
    public function offsetGet(mixed $o): mixed { return $this->d[$o] ?? null; }
    public function offsetSet(mixed $o, mixed $v): void { if ($o === null) $this->d[] = $v; else $this->d[$o] = $v; }
    public function offsetUnset(mixed $o): void { unset($this->d[$o]); }
}
$obj = new C;
$obj['k'] = 'v';
$obj[] = 'w';
echo "obj: ", json_encode($obj->d), "\n";
// ⑦ 字符串偏移读 + 嵌套
$s7 = "hello";
echo "read: $s7[1]$s7[4]\n";
// ⑧ 数组字面量函数内构建
function f_lit() {
    $t = ['p' => 7, 'q' => 8];
    echo "f-lit: ", json_encode($t), "\n";
}
f_lit();
