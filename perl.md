# perl

- 数据类型

三种：标量，数组，哈希

标量：$作为前缀标记，e.g. $a, $b
标量：@作为前缀标记，e.g. @a, @b
哈希: %作为前缀标记，e.g. %a, %b

- 变量

use strict 强制生命变量类型

标量：定义：$a=foo 访问 $a
标量：定义：@a=(1,2,3) 访问 $a[0]
哈希: 定义：%a=('foo',1,'bar',2) 访问 $a{'foo'}

变量上下文：
上下文由=左边的变量类型决定，上下文不同赋值的含义不同；

- 运算符

引号运算符
q{}     为字符串添加单引号
qq{}    为字符串添加双引号
qx{}    为字符串添加反引号


- 函数

定义：
sub subroutine {
    # 函数体
}

调用：

subroutine(#参数列表)
&subroutine(#参数列表) #5.0以下版本调用方法，5.0以上不推荐

参数：
参数数组用@_表示, 第一个参数为$_[0], 第二个为$_[1]
默认参数按照引用方式传递

- 特殊标量
    1. $_ $ARG
    表示默认输入（foreach，函数）
    2. $. $NR
    文件句柄的当前行号
    3. $/ $RS 
    输入记录分隔符，默认为\n
    4. $, $OFS 
    输出域分隔符
    5. $\ $ORS 
    输出记录分隔符
    6. $" $LIST_SEPARATOR
    类似$,
    7. $; $SUBSCRIPT_SEPARATOR
    多维数组分隔符，默认"\034"
    8. $? $CHILD_ERROR
    子函数输出值
    9. $! $OS_ERROR or $ERRNO
    errno
    10. $@ $EVAL_ERROR
    11. $$ $PROCESS_ID or $PID
    12. $< $REAL_USER_ID or $UID
    13. $( $REAL_GROUP_ID or $GID
    14. $0 $PROGRAM_NAME
    15. $] $PERL_VERSION
    16. $^D $DEBUGGING
    
- 特殊数组

    1. @ARGV
    2. @INC
    3. @F

- 特殊哈希

    1. %INC
    2. %ENV
    3. %SIG

- 特殊文件句柄
    1. ARGV
    2. STDERR
    3. STDIN
    4. STDOUT
    5. DATA
    6. _ 

- 特殊正则表达式变量

    1. $n
    2. $& $MATCH
    3. $` $PREMATCH
    4. $' $POSTMATCH
    5. $+ $LAST_PAREN_MATCH


- 正则表达式

三种命令：

1. 匹配: m//（还可以简写为//，略去m）
2. 替换: s///
3. 转化: tr///

这三种形式一般都和 =~ 或 !~ 搭配使用， =~ 表示相匹配，!~ 表示不匹配。


- 库函数


shift 数组pop函数

