# cpp

## reference

概念：

alias - not a pointer to x, nor a copy of x, but x itself. can be taken address, &alias == &x.

under the hood:

通常都是用指针来实现引用的，但是在概念理解上应该理解为别名。

应用场景：

1) pass by ref
2) return by ref (operator[], operator<<)

为什么引入pointer和ref概念：

引入pointer是为了兼容C；
引入ref是为了优雅实现operator overloading；

ref和pointer的使用准则：

Use references when you can, and pointers when you have to.

https://isocpp.org/wiki/faq/references

## name-hiding

如果derived override了base的函数funcA，那么funcA的其他overload都被hide。可以使用
using关键词unhide base的funcA。

name-hiding的原因是，为了符合人类的直觉：derived的函数族不应该和base的函数族混合
在一起，否则有可能产生很奇葩的组合结果。因此，c++ overload会有hide的副作用。

c++的设计者认为no name-hiding比name-hiding更加evil。

参考材料：https://stackoverflow.com/questions/1628768/why-does-an-overridden-function-in-the-derived-class-hide-other-overloads-of-the

## 智能指针

### shared_ptr

```
shared_ptr := (
    obj_ptr
    control_block := (
        deleter
        allocator
        shared_ptr_cnt
        weak_ptr_cnt
        obj or obj_ptr //托管对象或者托管对象的指针
    )
)
```

ctor: shared_ptr_cnt = 1 （如果make_shared则malloc一次，；如果通过ctor则malloc两次）
copy: shared_ptr_cnt++
dtor: shared_ptr_cnt--, if cnt==0，delete obj

通过引用传入shared_ptr<obj>，通过拷贝shared_ptr<obj>持有obj的引用。

### unique_ptr

```
unique_ptr := (
    obj_ptr
)

```

由于unique_ptr不允许拷贝和赋值，因此当unique_ptr执行dtor时，ptr将被delete。

std::move 也就是强制转换为rvalueref，最后拷贝调用的也是mtor。

而unique_ptr的mtor直接将ptr的指针转到新的unique_ptr，并且将obj_ptr置为空，最后
dtor时就不会再把obj给delete掉了。

## ctor & dtor

对象获得内存（无论是堆内存还是栈内存）ctor被调用：
释放对象内存（无论是堆内存还是栈内存）ctor被调用：

具体而言：

a) ctor

栈对象a压栈，那么a持有的成员对象ctor被调用，a的ctor被调用
堆对象a被new，那么a持有的成员对象ctor被调用，a的ctor被调用

b) dtor

栈对象a弹栈，那么a持有的成员对象dtor被调用，a的dtor被调用
堆对象a被free，那么a持有的成员对象dtor被调用，a的dtor被调用

综上：ctor随着对象内存创建被调用，dtor随着对象内存释放被调用。

# c

## assert.h

如果定义了NDEBUG宏，则不产生任何代码，否则产生assert代码。

## 数据结构

### TAILQ

为什么`struct type **tqe_prev`和`struct type **tailq_last`，但adlist定义
为`struct listNode *next`？

主要的目的是为了减少if分支。

## 基础

### inline

### double

double 包含nan, inf。

```
-inf + <any double but +inf> => -inf
-inf + +inf => nan
-inf == -inf
+inf == +inf
-inf < <any double but -inf>
+inf > <any double buf +inf>
```

## limits

`sizeof(long)`和`sizeof(void*)`相等：long的长度与指针相同


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

* time
<time.h>

 time_t 精卻倒s的時間
time_t - c standard did't specify the time_t, but almost implementations define it as int - 
seconds from epoch, it may fail on 2038.
time_t time(time_t *arg);

clock 通常用来统计进程使用的cpu时间
clock_t - representing the processor time used by a process.
clock_t clock(void);
CLOCKS_PER_SEC



NOTE 统计进程使用的时间clock_gettime的精度更好 
http://en.cppreference.com/w/c/chrono/clock

struct timespec {
    time_t   tv_sec;        /* seconds */
    long     tv_nsec;       /* nanoseconds */
};

int clock_gettime(clockid_t clock_id, struct timespec *tp); 
CLOCK_PROCESS_CPUTIME_ID


 timespec

int timespec_get( struct timespec *ts, int base)
#define TIME_UTC /* implementation defined */

 conversion 
1. tm -> ascii
char* asctime( const struct tm* time_ptr );
errno_t asctime_s(char *buf, rsize_t bufsz, const struct tm *time_ptr);

2. time_t -> tm
struct tm *localtime( const time_t *time );
struct tm *localtime_s(const time_t *restrict time, struct tm *restrict result);

3. time_t -> ascii
char* ctime( const time_t* time );
errno_t ctime_s(char *buffer, rsize_t bufsz, const time_t *time);

4. time_t -> tm
struct tm *gmtime( const time_t *time );
struct tm *gmtime_s(const time_t *restrict time, struct tm *restrict result);

5. tm -> time_t
time_t mktime( struct tm *time );

总结:这么多的时间，都没有精度高的calender time

<sys/time.h>
struct timeval {
    time_t      tv_sec;     /* seconds */
    suseconds_t tv_usec;    /* microseconds */
};

int gettimeofday(struct timeval *tv, struct timezone *tz);
能获取us精度的时间，但是注意这个时间是可以被系统管理员修改的！

<time.h>
int clock_gettime(clockid_t clk_id, struct timespec *tp);
CLOCK_MONOTONIC

能够获取us精度的时间，这个时间不会被修改


* does it make sense to strncpy(dst, src, strlen(src) + 1) ????

* ansi c boolean type is int

* snprintf(char *buf, size_t size, const char *format, ...) 是一个复杂的函数:

几个问题：

1. 是不是snprintf之后buf总是null-terminated? 

如果size > 0； 如果size = 0不会对buf有任何操作

linux平台的snprintf总是null-terminated的;windows平台只有_snprintf，不是null-terminated

2. 返回值的含义？

表示如果buf足够大，encode到buf的字符数（不包括\0)

注意，如果被truncated，返回值可能与一些programmer预期的结果不一致，因此另外一个函数

_scnprintf(char *buf, size_t size, const char *format, ...)

_scnprintf与snprintf的行为一致，除了_scnprintf返回的是真正写入到buf的字节数（不包括\0)

3. 如何判断被truncated

返回值 >= size

4. 示意例程：
```

#include <stdio.h>

int main()
{
    char buf[5];
    int ret;

    ret = snprintf(buf, sizeof(buf), "%s", "hello");

    printf("%d: %s\n", ret, buf);

    return 0;
}
```
输出

```
5 hell
```



* char *strncpy(char *dst, const char *src, size_t n)

是不是dst总是null-terminated?

NO！ 如果src的前n个字节没有\0，dst将不是null-terminated (c string).

## TAILQ

bsd发行的列表（队列）头文件, 实现全部用宏。

```c
#define TAILQ_HEAD(name, type)						\
struct name {								\
	struct type *tqh_first;	/* first element */			\
	struct type **tqh_last;	/* addr of last next element */		\
}
```

- 为什么tqh_first是一级指针，tqh_last是一个二级指针？
- type是不是必须是TQILQ_ENTRY?

```c
#define TAILQ_ENTRY(type)						\
struct {								\
	struct type *tqe_next;	/* next element */			\
	struct type **tqe_prev;	/* address of previous next element */	\
}
```

- 为什么tqe_next是一级指针，而tqe_prev是二级指针
>>>>>>> e8cfc83926167c3fc0ecbcebc23cf4c258b44ac1


## feature test macros

# 健壮性

## valgrind

```
valgrind --leak-check=full --show-leak-kinds=definite,possible --track-fds=yes --log-file=vlg.log --suppressions=supp <bin>

valgrind: make CFLAGS="-O0 -g"
```


## gcov

```
gcov:
	${MAKE} CFLAGS="-fprofile-arcs -ftest-coverage" LDFLAGS="-fprofile-arcs"

coverage:
	make check 
	mkdir -p tmp/lcov
	lcov -d . -c -o tmp/lcov/xxx.info
	genhtml --legend -o tmp/lcov/report tmp/lcov/xxx.info
```


upredis产品发布前的增量覆盖率测试方法：

a) upredis

```
# 1. 安装依赖
./make.sh 

# 2. 编译gcov binnary
make clean
make REDIS_CFLAGS="-fprofile-arcs -ftest-coverage -DCOVERAGE_TEST" REDIS_LDFLAGS="-fprofile-arcs -ftest-coverage" OPTIMIZATION="-O0" MALLOC="libc"

# 3. 运行
valgrind --leak-check=full --show-leak-kinds=definite,possible --log-file=valgrind.log redis-server redis.conf

# 4. 运行案例
...

# 5. 生成报告
修改src/Makefile（注释掉编译和自动案例运行)
make increment-lcov

# 6. 分析报告
valgrind.log
src/lcov-html
```

b) upredis-proxy

```

```

c) upredis-tool




# 网络

## iptables

```
iptables -A INPUT -p tcp --dport 33301 -j DROP
iptalbes -L --line-numbers
iptables -D INPUT 1
```

# 内存

## gperftools

```
env LD_PRELOAD="/usr/lib64/libtcmalloc.so" HEAPPROFILE=/home/srzhao/rmt/rmt.heap ./redis-migrate-tool -c rmt.conf
pprof --pdf --base=/tmp/profile.0004.heap ./redis-migrate-tool /tmp/profile.0100.heap > rmt.pdf
```

## massif

```
valgrind --tool=massif prog
ms_print massif.out.12345
```

##

