#######################

* 关于typedef和struct
参考回答：http://stackoverflow.com/questions/252780/why-should-we-typedef-a-struct-so-often-in-c

* remove trailing '\n' (fgets)
buf[strcspn(buf, '\n')] = 0;

* strdup & strdupa 比 malloc;strcpy 更简洁

* extern IS OPTIONAL on function

* uint32_t defined in stdint.h

* size_t defined in stddef.h

* strspn(const char *s, const char *accept);
    找到s中全由accept中字符组成的连续长度

* strtok
    split string 

* strpbrk - search a string for any of a set of bytes

* goto label, label only have function scope

* restrict c99 keyword, intend for compiler, its' programmer promise of elimiating pointer aliasing

#######################

## 一些疑问

* malloc 失败是否需要返回判断错误，打印消息，并且处理该错误？

libevent 不处理，只打印消息。

我觉得, 既然malloc失败了（也就是OOM）,这个时候程序只能退出！区别在于退出的姿势，是主动退出呢？还是core掉。
从友好性来讲，应该主动退出; 但是core掉应该也是没有啥问题的吧。



* 如何将vim和gdb结合起来

不结合比较简单，出问题应该主要从log判断

