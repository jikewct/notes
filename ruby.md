# ruby

类似于python，perl的面向对象解释性语言。

## basics

### 数据类型

Fixnum -- 4B
Bignum -- 8B
Double 
String 
Array
Hash
Range

### 变量

```
小写字母、下划线开头：变量（Variable）。
$开头：全局变量（Global variable）。
@开头：实例变量（Instance variable）。
@@开头：类变量（Class variable）类变量被共享在整个继承链中
大写字母开头：常数（Constant）。
```

### 注释

```
# single line comment

=begin
multi
line
comment
=end
```

## 语法

基本上和shell的语法很像，比较有意思的是block语法：block被迭代器迭代调用。

## Ticks

```
puts "result : #{24*60*60}"; # 
```
