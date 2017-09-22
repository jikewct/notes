# 协程调研

目前在github上有libco，lthread，coroutine, libgo等的开源c/c++协程实现。

c++ boost库含有比较完整协程设计，包括boost.Context上下文组件，boost.Coroutine
协程组件, 以及boost.asio异步IO组件。

阅读分析了其中的libco, lthread, coroutine源码(由于libgo，boost使用了大量
的c++11特性，暂时没有阅读), 对以上开源实现进行简单介绍，并分析对比
各实现的特点。

## why corotine?

近年来，随着golang的发展，其内置goroutine且适合网络IO编程的特性使得
协程概念得到更多后端开发的关注。

此外，异步回调的解决方案使得业务逻辑分散在各种回调碎片中，增加了业务
开发的难度, 特别是逻辑很长的业务。

多线程虽然相对于多进程的创建和切换效率更高，但是仍然需要陷入内核做线程切换
创建过多线程会显著增加调度损耗的性能。

协程作为一种用户级“线程”，可以用看似同步的逻辑开发高性能异步程序，能显著
提高开发效率。

关于协程值得注意的地方：

- 历史上先有协程再有线程，是OS用来模拟多任务的。但是由于协程不可抢占，导致
  任务时间片不能公平分享，后来废弃并改为抢占式的线程。

- 多协程与多线程相比，不能友好地利用多核。

- 虽然在网络服务端协程的概念比较新，但是在游戏领域（大量的角色和很长的逻辑）
  很早就已经应用。

## tutorial

使用[cloudwu/coroutine](https://github.com/cloudwu/coroutine)的示例代码,
展示下协程的原语：


```c
#include "coroutine.h"
#include <stdio.h>

struct args {
	int n;
};

static void
foo(struct schedule * S, void *ud) {
	struct args * arg = ud;
	int start = arg->n;
	int i;
	for (i=0;i<5;i++) {
		printf("coroutine %d : %d\n",coroutine_running(S) , start + i);
		coroutine_yield(S);
	}
}

static void
test(struct schedule *S) {
	struct args arg1 = { 0 };
	struct args arg2 = { 100 };

	int co1 = coroutine_new(S, foo, &arg1);
	int co2 = coroutine_new(S, foo, &arg2);
	printf("main start\n");
	while (coroutine_status(S,co1) && coroutine_status(S,co2)) {
		coroutine_resume(S,co1);
		coroutine_resume(S,co2);
	} 
	printf("main end\n");
}

int 
main() {
	struct schedule * S = coroutine_open();
	test(S);
	coroutine_close(S);
	
	return 0;
}

```

## 协程原语

coroutine_open          创建调度器
coroutine_close         关闭调度器
coroutine_new           创建协程
coroutine_resume        恢复协程执行（启动协程）
coroutine_yield         协程交出控制权限

## 协程状态

一个进程的执行状态包括CPU状态（寄存器状态），栈内存，堆内存三种。

由于同一进程堆内存共享，因此堆内存状态（pagetable）无需保存；

栈内存保存了协程的自动变量、函数参数等，需要保存。

CPU状态即寄存器状态，表示了当前执行状态，需要保存。

## 协程切换

协程切换讲当前协程的执行状态保存，并切换到待执行的协程。通常实现方法包括
- ucontext
- setjmp/longjmp
- 汇编

其中汇编实现基本没有可移植性，ucontext在posix系统中都可以移植。

## stack

协程栈常见实现分为共享栈和独享栈:

- 独享栈: 在协程创建时，malloc一块内存作为coroutine的协程栈
- 共享栈: 多协程使用同一块内存作为协程栈；在yield/resume时需要save/restore栈内存

## 协程调度

调度策略分为两种

- yield to prev
- yield to scheduler

yield to prev, 协程yield时将执行权限交给父协程；

yield to scheduler，协程yield时将执行权限交给调度器；

## [cloudwu/coroutine](https://github.com/cloudwu/coroutine)

特点：
- ucontext切换
- 独享栈
- yield to scheduler

实现简单，代码整洁，能搞较好地展示协程概念。可以在协程总数较小且能忍
受栈内存拷贝的场景使用。

## [Tencent/libco](https://github.com/Tencent/libco)

特点：
- 汇编切换
- 独享栈/共享栈可选
- yield to prev
- hook网络编程API(除accept)

设计初衷是用于移植微信同步后台程序，目前在微信中广泛使用。由于hook了网络

据称支持千万量级协程，性能优秀。

用法：

```
static void *readwrite_routine( void *arg )
{
    co_enable_hook_sys(); /* hook 网络IO函数 */

    ...

    for(;;) {   
        if ( fd < 0 ) {   
            fd = socket(PF_INET, SOCK_STREAM, 0); /* fd在hook函数中被设置为nonblock*/
            struct sockaddr_in addr;
            SetAddr(endpoint->ip, endpoint->port, addr);
            ret = connect(fd,(struct sockaddr*)&addr,sizeof(addr)); /* connect 函数中poll fd，并且处理EINPROGRESS */
            if (ret < 0) {
                close(fd); 
                fd = -1;
                continue;
            }

            ret = write( fd,str, 8);    /* EAGAIN则poll，并发送完整请求数据 */
            if ( ret > 0 ) {
                ret = read( fd,buf, sizeof(buf) ); /* EAGAIN则poll */
                if ( ret <= 0 ) {
                    close(fd);
                    fd = -1;
                    AddFailCnt();
                } else {
                    AddSuccCnt();
                }
            } else {
                close(fd);
                fd = -1;
                AddFailCnt();
            }
        }
    }
}

int main(int argc,char *argv[])
{
    ...
    for(int i=0;i<cnt;i++) {
        stCoRoutine_t *co = 0; 
        co_create( &co,NULL,readwrite_routine, &endpoint);
        co_resume( co );    /* cpu执行权交给co。co_resume返回时co已经执行完成或者阻塞
                               如果阻塞则添加到线程对应的epoll中，等待事件触发*/
    }

    co_eventloop( co_get_epoll_ct(),0,0 ); /* 等待事件触发或者timeout，
                                            然后从event_data中获取对应的co，执行co_resume*/
    ...
}

```

共享栈：

1. 每个线程都有若干个共享栈（降低保存/恢复概率）
2. 在协程切换前，保存共享栈（将esp~ebp之间的内存拷贝到malloc的save_buf）
3. 在协程切换后, 恢复共享栈（将save_buf中的内存拷贝到esp~epb之间）


注意：

一个fd只能在一个co中使用！


## [halayli/lthread](https://github.com/halayli/lthread)

特点：
- 汇编切换
- 独享栈
- yield to sceduler
- 支持CPU密集操作
- 支持disk IO

lthread与libco的实现思路类似，比较新颖的是lthread考虑了CPU密集
和disk IO操作。

支持CPU密集和disk IO操作：

创建worker线程
当前协程co_yield(co)
worker完成 ops(CPU密集或者disk IO)
worker向事件循环发送完成事件
事件循环co_resume(co)


## [yyzybb537/libgo](https://github.com/yyzybb537/libgo)

特点：
- boost.Context切换
- 独享栈
- yield to scheduler
- hook了所有网络API
- 支持多线程，可以有效利用多核

用于运用的c++11的特性较多，暂且没有阅读。

## 总结

- 协程在处理IO密集，业务逻辑链较长的程序比较有优势
- libco是调研项目中质量较高，并且生产环境测试比较完备的协程库


-----
TODO


1. 其他语言的协程
2. boost.Context和boost.Coroutine以及boost.asio
3. 
