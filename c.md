
# limits

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


## 一些疑问

* malloc 失败是否需要返回判断错误，打印消息，并且处理该错误？

libevent 不处理，只打印消息。

我觉得, 既然malloc失败了（也就是OOM）,这个时候程序只能退出！区别在于退出的姿势，是主动退出呢？还是core掉。
从友好性来讲，应该主动退出; 但是core掉应该也是没有啥问题的吧。



* 如何将vim和gdb结合起来

不结合比较简单，出问题应该主要从log判断

=======
* time
<time.h>

### time_t 精卻倒s的時間
time_t - c standard did't specify the time_t, but almost implementations define it as int - 
seconds from epoch, it may fail on 2038.
time_t time(time_t *arg);

###clock 通常用来统计进程使用的cpu时间
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


### timespec

int timespec_get( struct timespec *ts, int base)
#define TIME_UTC /* implementation defined */

### conversion 
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

# TAILQ

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
