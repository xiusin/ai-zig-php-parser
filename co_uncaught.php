<?php
// co_uncaught：协程内 throw 未捕获 ⇒ 整程序致命（设计 D1=A；rc=255，文案含协程 id）（设计稿 §5 M1 探针 5）。
function boom() {
    throw new RuntimeException("kaboom");
}
// ★注：赋值形 go 调用（$id = go(...)）规避裸 go(...) 语句命中 Go 语法 go_stmt 解析的预存缺陷（已上报）。
$id = go('boom');
go_wait_all();
echo "co_uncaught FAIL: reached end\n";
