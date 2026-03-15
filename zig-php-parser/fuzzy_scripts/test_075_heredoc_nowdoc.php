<?php
// 测试75: Heredoc和Nowdoc语法
$name = "World";
$number = 42;

// Heredoc（解析变量）
$heredoc = <<<EOT
Hello, $name!
The number is: $number
This is a multiline
string with 	 tabs and 
 newlines.
EOT;

echo "Heredoc:
$heredoc

";

// Nowdoc（不解析变量）
$nowdoc = <<<'EOT'
Hello, $name!
The number is: $number
No variable parsing here.
EOT;

echo "Nowdoc:
$nowdoc

";

// 带缩进的Heredoc（PHP 7.3+）
$indented = <<<EOT
    This is indented
        Even more indented
    Back to level 1
EOT;
echo "Indented:
$indented
";

// 在函数中使用
function formatMessage(string $user): string {
    return <<<MSG
Dear $user,

Welcome to our service!

Regards,
The Team
MSG;
}

echo formatMessage("Alice") . "
";
?>