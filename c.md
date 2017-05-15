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
