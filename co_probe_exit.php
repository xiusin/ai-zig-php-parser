<?php
// 临时探针：go 后 main 未阻塞直接结束 ⇒ 未完成协程是否致命
function w_exit() {
    $x = 1;
}
go('w_exit');
echo "main_return\n";
