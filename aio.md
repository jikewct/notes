# aio

aio与epoll都是为了解决io与cpu速度不匹配问题的解决方案。epoll通过轮询多个fd提高效率，但仍然是同步的处理方式；
而aio则是异步的处理方式，允许在io没有完成的情况下继续进行（不需要等待io完成的）其他操作。

aio用来改善吞吐量，延时和响应性。但是aio通常会带来资源争用，需要更加细心的避免这些问题。

## 实现

### kernel native aio

NOTE: kernel-native aio需要按照libaio, linux-2.5之后才有aio

API:

    int io_setup(unsigned nr_events, aio_context_t *ctxp);
    int io_destroy(aio_context_t ctx);
    int io_submit(aio_context_t ctx, long nr, struct iocb *cbp[]);
    int io_cancel(aio_context_t ctx, struct iocb *, struct io_event *result);
    int io_getevents(aio_context_t ctx, long min_nr, long nr,
                struct io_event *events, struct timespec *timeout);



### posix aio

    概述
    

    API
    aio_read(3)     Enqueue a read request.  This is the asynchronous analog of read(2).
    aio_write(3)    Enqueue a write request.  This is the asynchronous analog of write(2).
    aio_fsync(3)    Enqueue a sync request for the I/O operations on a file descriptor.  This is the asynchronous analog of fsync(2) and fdatasync(2).
    aio_error(3)    Obtain the error status of an enqueued I/O request.
    aio_return(3)   Obtain the return status of a completed I/O request.
    aio_suspend(3)  Suspend the caller until one or more of a specified set of I/O requests completes.
    aio_cancel(3)   Attempt to cancel outstanding I/O requests on a specified file descriptor.
    lio_listio(3)   Enqueue multiple I/O requests using a single function call.
    aio_init(3)     Set parameters for tuning the behavior of the glibc  POSIX  AIO  implementation.

    数据结构
    struct aiocb {
        /* The order of these fields is implementation-dependent */

        int             aio_fildes;     /* File descriptor */
        off_t           aio_offset;     /* File offset */
        volatile void  *aio_buf;        /* Location of buffer */
        size_t          aio_nbytes;     /* Length of transfer */
        int             aio_reqprio;    /* Request priority */
        struct sigevent aio_sigevent;   /* Notification method */
        int             aio_lio_opcode; /* Operation to be performed;
                                           lio_listio() only */

        /* Various implementation-internal fields not shown */
    };
    /* Operation codes for 'aio_lio_opcode': */
    enum { LIO_READ, LIO_WRITE, LIO_NOP };

### sigevent

    sigevent - structure for notification from asynchronous routines

    SYNOPSIS
    union sigval {          /* Data passed with notification */
        int     sival_int;         /* Integer value */
        void   *sival_ptr;         /* Pointer value */
    };

    struct sigevent {
        int          sigev_notify; /* Notification method */
        int          sigev_signo;  /* Notification signal */
        union sigval sigev_value;  /* Data passed with
                                      notification */
        void       (*sigev_notify_function) (union sigval);
        /* Function used for thread
           notification (SIGEV_THREAD) */
        void        *sigev_notify_attributes;
        /* Attributes for notification thread
           (SIGEV_THREAD) */
        pid_t        sigev_notify_thread_id;
        /* ID of thread to signal (SIGEV_THREAD_ID) */
    };

## 一些疑问
    aio_init manpage 中提到aio的默认线程数量为20，这应该说明aio不适宜处理大量fd（aio manpage中也提到这个问题）, 没有可用线程时直接加入request queue!!
    关于clogs中的save线程是否不需要hash映射，因为本身的异步写已经实现了这部分功能。


## 二手资料

http://www.lenky.info/archives/2013/01/2165 (解读比较深入）
glibc aio的实现原理: 
    1、异步请求被提交到request_queue中；
    2、request_queue实际上是一个表结构，”行”是fd、”列”是具体的请求。也就是说，同一个fd的请求会被组织在一起；
    3、异步请求有优先级概念，属于同一个fd的请求会按优先级排序，并且最终被按优先级顺序处理；
    4、随着异步请求的提交，一些异步处理线程被动态创建。这些线程要做的事情就是从request_queue中取出请求，然后处理之；
    5、为避免异步处理线程之间的竞争，同一个fd所对应的请求只由一个线程来处理；
    6、异步处理线程同步地处理每一个请求，处理完成后在对应的aiocb中填充结果，然后触发可能的信号通知或回调函数（回调函数是需要创建新线程来调用的）；
    7、异步处理线程在完成某个fd的所有请求后，进入闲置状态；
    8、异步处理线程在闲置状态时，如果request_queue中有新的fd加入，则重新投入工作，去处理这个新fd的请求（新fd和它上一次处理的fd可以不是同一个）；
    9、异步处理线程处于闲置状态一段时间后（没有新的请求），则会自动退出。等到再有新的请求时，再去动态创建； 

openonload,lighttpd (lighty) 采用了异步io进行实现。

http://stackoverflow.com/questions/8768083/difference-between-posix-aio-and-libaio-on-linux aio的主要缺点是无法处理大量的fd

http://stackoverflow.com/questions/87892/what-is-the-status-of-posix-asynchronous-i-o-aio

知乎上评论：
    不成熟。glibc 的 aio 有 bug , kernel 的 aio 只能以 O_DIRECT 方式做直接 IO , libeio 也是 beta 阶段。epoll 是成熟的，但是 epoll 本身是同步的。Linux 上目前没有像 IOCP 这样的成熟异步 IO 实现。
