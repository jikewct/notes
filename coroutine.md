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

# coroutine调研（续）

## c#语言async/await

https://www.zhihu.com/question/30601778
知乎的观点是：await修饰的函数返回的是一个Task。


其他有用的信息：
async enable await
await waits on Task or Task<T>，不是async
await的语义:await将函数分成两部分，await之前的同步执行，await的Task开始执行，await之后的代码
尚未开始执行；await的Task执行完成之后，开始执行await之后的代码

async/await也还是在IO-bound的操作中比较有效，也就是还是需要借助于操作系统的
IO操作和时间触发机制。


## 迭代器概述

c# 中的yield是迭代器的基础，迭代器是LINQ中延迟查询的基础。

基本理念与c/c++的迭代器类似，但是c#产生迭代器和使用迭代器的方式不太相同。
一般c/c++迭代器含有hashNext，next接口；而c#则通过yield return获取next，
通过yield break结束迭代。


c# 迭代器概述：

- 迭代器是可以返回相同类型的值的有序序列的一段代码。
- 迭代器可用作方法、运算符或 get 访问器的代码体。
- 迭代器代码使用 yield return 语句依次返回每个元素。 yield break 将终止迭代。
- 可以在类中实现多个迭代器。 每个迭代器都必须像任何类成员一样有唯一的名称，
    并且可以在 foreach 语句中被客户端代码调用，如下所示：foreach(int x in SampleClass.Iterator2){}。
- 迭代器的返回类型必须为 IEnumerable、IEnumerator、IEnumerable<T> 或 IEnumerator<T>。
- 迭代器是 LINQ 查询中延迟执行行为的基础。


```c#
public class DaysOfTheWeek : System.Collections.IEnumerable
{
    string[] days = { "Sun", "Mon", "Tue", "Wed", "Thr", "Fri", "Sat" };

    public System.Collections.IEnumerator GetEnumerator()
    {
        for (int i = 0; i < days.Length; i++)
        {
            yield return days[i];
        }
    }
}

class TestDaysOfTheWeek
{
    static void Main()
    {
        // Create an instance of the collection class
        DaysOfTheWeek week = new DaysOfTheWeek();

        // Iterate with foreach
        foreach (string day in week)
        {
            System.Console.Write(day + " ");
        }
    }
}
// Output: Sun Mon Tue Wed Thr Fri Sat

```


## boot相关的概念

boost.Coroutine中的协程基本上是Generator模式，与c# yield return x; yield break;比较像
anyway，not easy to comprehend。


## golang & goroutine

golang是很早引入routine的语言，goroutine是怎么设计的？
waitgroup是怎么实现的？

### goroutine

- 关键字go声明函数是一个goroutine
- 没有看到yield原语

### channel

- 用来在goroutine之间进行数据传递的设施
- msg=make(chan type); msg <- "ping"; msg := <- msg; by default channel block untill sender/receiver ready;
- msg=make(chan string, 2), 则msg缓冲区大小为2;
- channel可以用于同步
- channel可以在传参的时候指定方向，这样可以增加类型安全
- go含有类似于网络IO语义的select
- time.After可以提供定时器（timeout）
- select带有default分支就是一个non-blocking的select
- close用于关闭channel, 关闭之后的channel仍然可以取出来消息, 这点与c的close不太相同
- timer在go中表示在未来的某个时间将会产生一个时间（通过channel），可以在时间发生前取消
- ticker产生心跳事件
- 使用goroutine，channel能够轻易地实现类似worker pool和流量控制（能够提供一些关于worker池和流量控制的思路）
- sync/atomic可以用来做原子计数
- goroutine并不一定在同一个线程中，因此获得线程安全的能力，需要通过互斥机制
- 实际上golang更加倾向于使用go的内置同步能力channel来完成同步互斥任务。通过channel能够保证每份数据只在一个协程中出现

### 总结
- goroutine实际上线程池上的协程。既可以利用多核能力，用能同步写代码，非常棒。
- 协程内部同步，协程之间并发


## libgo

goroutine没有了线程的概念，但是依然能够利用多核能力。

在模型上goroutine之间不是线程安全的！从这一点上来看goroutine更加类似于线程池。

非线程安全的goroutine需要通过mutex或者channel来进行数据的同步互斥。

另外，libgo提供了goroutine的一种理解方式。

### 使用到的c++11特性

- std::function

Class template std::function is a general-purpose polymorphic function wrapper. Instances of std::function can store, copy, and invoke any Callable target -- functions, lambda expressions, bind expressions, or other function objects, as well as pointers to member functions and pointers to data members.

- std::bind
The function template bind generates a forwarding call wrapper for f. Calling this wrapper is equivalent to invoking f with some of its arguments bound to args.

- mutable lambda

It requires mutable because by default, a function object should produce the same result every time it's called. This is the difference between an object orientated function and a function using a global variable, effectively.

- std::lockguard

The class lock_guard is a mutex wrapper that provides a convenient RAII-style mechanism for owning a mutex for the duration of a scoped block.

- RAII

Resource acquisition is initialization

- 智能指针

unique_ptr: 只允许一个所有者，可以移动到新的所有者，但是不会复制和共享
shared_ptr: 引用计数指针
weak_ptr:   结合shared_ptr的特例指针，引用对象但不参与计数
std::enable_shared_from_this : 让该对象能够被shared_ptr进行引用计数

### 调度

- 线程中调用了co_sched.Run()，那么当前线程参与调度
- routine所在的线程可以通过参数指定（rr，或者其他）
- co_yield，交出当前co的执行权
- libgo已经hook了read，write，connect，accept，但是依然需要在read和connect时处理EAGAIN？
- 之所以coro之间的锁重要，是因为coro在等待锁的期间可以直接yield，从而不会引起
- 提供了co_sleep, co_timer_add之类的接口，来解决频繁的定时器需求
- libgo真的是在认真考虑线程与coro之间的关系, 这很重要。libgo用了worksteal算法调度
- 给出了一个使用curl进行多并发进行http压测的简单工具
- channel与goroutine的几乎昰一致的特性（线程安全，阻塞等）
- 提供了await操作，用来等待真正会引起阻塞的操作（diskIO，cpu-bound）

### 关注点

- 怎么实现原语/切换的？
- 调度器策略，算法，如何与多线程结合
- 居然还提供await这种机制，看看与lthread的区别

### 二手知识

https://www.zhihu.com/question/20862617

goroutine的调度策略：work-steal？
- M（线程）P（上下文）G（协程）三种元素，M与G是N：M对应关系的
- 每个P当前执行一个G，并有一个就绪队列runqueue
- 如果P的runqueue为空，则从其他P中steal half
- 如果M当前阻塞，则P转移到其他M中执行；当M唤醒，则steal P;如果steal成功，则继续执行，否则 将G放入到global runqueue
- 所有的P都会定期查看global queue任务

### 总结

- c++ 版本的goroutine，比较重量
- 使用libevent也会遇到需要进行数据互斥(临界区)和通知(pipe)，因此co中也可以以类似的思路解决

### 源码解读

- coroutine做的任务分为(enum run flag)
            erf_do_coroutines   = 0x1,
            erf_do_timer        = 0x2,
            erf_do_sleeper      = 0x4,
            erf_do_eventloop    = 0x8,
            erf_idle_cpu        = 0x10,
            erf_signal          = 0x20,
            erf_all             = 0x7fffffff,

调度器Run所做的操作与类型相关，以上几种类型的任务都已DoXX进行处理

- M(ThreadLocalInfo)实际操作由proc->Run(也就是P)处理, 如果当前P runqueue为空，则从其他P中steal half（这里作者直接
随机选择一个P，然后stealhalf，为什么不找G最多的那个P）。

- 每一轮都处理已超时的timer
- sleep_wait?
- 为什么在runtask>0的时候Epoll的超时时间为0，而且为什么要epoll？居然是io_wait的时候epoll
- 调度器中居然有空转，这个简直不能忍呀！
- epoll不会在执行器中立即执行协程，而是将其放入到当前线程的就绪队列中
- 为什么yield能够直接yield给tls context？如果有多层goroutine，岂不是就直接回不来了？
- timer和sleep是一样的逻辑，为什么要分开？用法不一样吗？


### groundup 精读

#### context

Context类包含两个context：
1. tls context，也就是上次切换的时候保存的context
2. private context:
    每次swapIn: 保存当前context到tls, 执行private
    每次swapOut:保存当前context到private, 执行tls

问题：
- 如果main go A; A go B; B go C会不会出现回不到A的情况
:: 目前的逻辑确实与分析的相同，swapin则将交换到Task对应的context运行，否则交换到原先
   的context运行。

- 如果private context执行完成，由于makecontext设置的uc_link是NULL，那么当前的Task退出
  难道每次go执行完成了，当前线程都会退出？
::应该是的！
  
- 感觉上对于ucontext的理解还不够深入：
context到底包含哪些东西？
::包含寄存器，uc_link，sigmask,等等, stack, mcontext

为什么在makecontext之前需要getcontext，getcontext获取的寄存器状态还有用吗？如果没有用那为什么要get？直接makecontext不就好了？如果有用，那那些东西有用? 
:: 不清楚为什么get，但是get一下也无妨，就当init了；

通常uc_link 如何设置, 如何设置uc_link能使得重新返回到swapcontext之前的地方继续运行？
:: cloudwu将context设置为oucp, 这样就类似于调用了一个函数

为什么manpage中提到了多线程切换？如何切换到另一个线程？
:: 个人理解，应该不能在多线程之间切换，要切换也是int 80到内核切换


#### fd_context

包含以下组件：

FileDescriptorCtx : fd ctx
FdManager         : fd manager
IoSentry          : io state entry

##### IOSentry

- io state 一共两种 pending， triggerd。基本就能猜到是epoll触发事件之前，之后的状态
- 一个IoSentry应该是一次poll放入的fds（与libco类似），可能有多个fd，但一般是一个
- 一个entry只有一个State，但可能有多个fds
- switch_state_to_triggered表示将状态转换为triggered，一般是事件发生之后做的事情
- triggered_by_add 手动添加事件

##### FileDescriptorCtx

在libgo中明确允许fd被多个co等待，所以说libgo功能很多，但是c++，多线程等等是的阅读起来比较吃力
但是我们应该从其中获取一些经验，获得libco上有些功能上的缺失是可以用其他方法实现的。

表示的就是一个FD的相关属性，包括 是不是socket，是不是nonoblock，是不是, pending events,
epfd, epfd是否et模式

在libgo中，自作聪明地将epoll抽象名字为reactor， 所以其中的reactor_ctl就是epoll_ctl
- add_into_reactor 在做添加读写事件的工作，只不过多做一些与ctx相关的事情。
- reactor_trigger  epollwait产生了事件之后，将触发的事件放入到任务队列中。


##### FdManager

- fdManager管理了所有涉及的fds
- 最主要的是有一个fd->fdctx的大Map

#### io_wait

- 处理epoll相关的事情
- CoSwitch 就是yield
- SchedulerSwitch 就是讲Triggered放入到就绪列表中
- epoll能同时ET和LT 
- WaitLoop自作聪明地封装epoll_wait, 然后将triggered fd对应的sentry放入到runqueue中

#### scheduler

- M P G三个概念，

### block_object

- 居然是cond，又自作聪明地把wait，signal改成BlockWait, Wakeup, 真是比了够了。

### channel




### 测试libgo

1. sample9并发数量只能到1000，这个很令人失望！
2. 测试下来发现libgo的co_resume操作只能由scheduler，这样的话scheduler的context要么在tls中要么正在执行
   也就是说libgo下面的co在scheduler看来没有任何区别；而libco的co是父子调用关系。

### 总结

- libgo是FAC
- libgo的yield to scheduler
- libgo的调度器可以多线程，处理多线程的机制也比较简单，stealHalf
- 测试来看libgo的性能很不咋地, 处理超时和poll也没有libco elegent
- 能给我们带来的提示：最好解决libco fd不能再多co中使用的问题?
- 多线程的问题可能也不是问题


## revisiting coroutines

co广泛接受的概念只有: 连续的调用中能够保存状态

### 分类

1. symmetric vs asymmetric

symmetric : only have swap(from, to) operation.
asymmetric: have invoke & suspend operations. control always transfer back to it's invoker, behaves more like a routine
比如iterator，generator都是asymmetric

论文表达的观点是： 对称非对称都有相同的表达能力，但是asmmetric更容易理解

2. first-class vs constrained 

constrained: iterator, generator

3. stackfull vs stackless

论文重新强调了下对 full asymmetric coroutine的推崇

### full asym co

原语： 
create :创建但不执行
resume :(re)active, 执行完成后co处于dead状态，不能被再次resume
yield  :挂起当前co，并记住当前的状态

实例：lua

lua实现了与fac相同概念co

除了让我知道lua有FAC之外，没有提供更加有效的信息。
另外更加清晰了symmetric和asym的区别，至少libgo的是asym的，只不过libgo没有resume，只有yield。
因为libgo中只有scheduler有resume能力。

综上：libgo yield to scheduler，tls要么是main，要么没有！

cloudwu设计与Lua的coro一样，为什么cloudWu说他的co是asymmetric的呢？
因为他的设计也是用的yield，resume这样的。


coroutine.create()  创建coroutine，返回coroutine， 参数是一个函数，当和resume配合使用的时候就唤醒函数调用
coroutine.resume()  重启coroutine，和create配合使用
coroutine.yield()   挂起coroutine，将coroutine设置为挂起状态，这个和resume配合使用能有很多有用的效果
coroutine.status()  查看coroutine的状态 注：coroutine的状态有三种：dead，suspend，running，具体什么时候有这样的状态请参考下面的程序
coroutine.wrap（）  创建coroutine，返回一个函数，一旦你调用这个函数，就进入coroutine，和create功能重复
coroutine.running() 返回正在跑的coroutine，一个coroutine就是一个线程，当使用running的时候，就是返回一个corouting的线程号

可以得到一个启发，可以通过resume返回值，获取当前的co当次运行状态
通过swapcontext能返回值吗, 不能，但是我们可以利用co提前设置返回值, yield带参数进行返回 


libgo是不符合FAC规则co，因为每次都yield to scheduler，scheduler to runqueue.
那么问题来了，yield to scheduler之后啥时候在resume呢？谁来resume呢?
答案就是通过事件机制将对应的co放入到runqueue中，由事件callback将co放入到runqueue中。


虽然libgo在设计上非常重量，不够灵活，但是给出了一些启发，还是值得读一读的。

# libco

## 理解

协程是用户级线程，与线程相比，协程更加轻量，用户可以轻易地创建千万级线程，
每个协程处理一个同步的业务逻辑，从而以同步逻辑实现高并发。

网络编程有一种经典的IO模型: 单线程处理单链接。但由于操作系统的线程数量无能
过大（调度效率降低），该模型无法很好地处理高并发问题。

但是该模型变换为：单协程处理单链接。则可以通过用户空间的协程调度较好地解决
这个问题。

### naive

coroutine：

```
co = co_create
...
opA
opB
...
while !ready:
    co_yield(co)  /* yield to dispatcher */
...
opC
opD
...

co_release(co)
```

dispatcher：

```
co = co_next(co_queue)
swapto(co)

```

缺点：
> 协程yield(to dispatcher)，dispatcher轮询激活coroutine的策略, 会造成大量的无效切换
> 该策略虽然不修改同步代码逻辑，但是需要插入ready判断逻辑，同步代码移植不方便

### cond

调度效率的问题主要是唤醒非ready协程造成的，可以通过条件变量来解决调度的效率问题。

cv1 = co_cond_create
cv2 = co_cond_create

coroutine1:

```
co = co_create
...
opA
opB
...
co_cond_signal(cv1) // yield to dispatcher? TODO confirm
...
opC
opD
...
co_cond_wait(cv2)  // yield to dispatcher
...

co_release(co)
```

coroutine2:

```
co = co_create
...
opA
opB
...
co_cond_signal(cv2)
...
opC
opD
...
co_cond_wait(cv1)
...

co_release(co)
```

cond_signal(cv):

```
co = cond_co_next(cv)
swapto(co)
```

cond_wait(cv, co):      // 信号量会不会造成死锁？如果会造成死锁怎么办？libco怎么处理这个问题

```
cond_add_co(cv, co);
swapto(dispatcher)
```

dispatcher:
```
co = co_next        //TODO co_next or co_prev, why prev? how about starvation? 
swapto(co)
```


### libco goes beyond

libco除了以上功能之外，最主要的特点:
> hook网络API(connect, read, write...)，从而减少同步程序向协程迁移的修改
> 基于epoll的调度


hook网络API的基本思路为：libco提供与libc同名的网络API；链接时libco在libc之前，因此调用的是libco的
符号；libco在调用libco的API之前作如下逻辑处理：

```
if api(fd) would block:
    create mapping: fd <-> co
    add fd to epoll             // which event
    yield to dispatcher         // may be we just need swapto co_prev? 
else:
    co continue
```

基于epoll的调度:

```
epoll_wait(epfd, events, fds)
    foreach fd in fds:
        swapto(fd<->co)         // really? everytime?
```

## 协程切换

1. 寻址空间
2. 为什么我们一般不设置占内存？
3. 如何管理和设置占内存


### what's context

1. 寄存器
2. 内存
3. 函数调用站分析

### context swap



## 调度

除了基于epoll的调度，还有没有其他的调度？能不能抽象出来一个调度器?
会不会基于libevent的调度更加高效？

## TODO
1. 从更高的视角思考，验证，观察, 分析libco的调度策略
2. 调研其他语言的协程：python， lua， c#, java(generator, cloudwu的coroutine，swoole的corotine，lthread的实现）
3. 有些博客也有些比较有意思的观点：http://blog.csdn.net/screaming/article/details/51378468
4. libco的超时控制(平衡树）和内存控制（又来个slab？没必要吧）其实应该可以优化!

---- 分析cond
1. 分析理解数据结构:
stTimeout:
```
struct stTimeoutItem_t
{

	enum
	{
		eMaxTimeout = 40 * 1000 //40s
	};
	stTimeoutItem_t *pPrev;
	stTimeoutItem_t *pNext;
	stTimeoutItemLink_t *pLink;

	unsigned long long ullExpireTime;

	OnPreparePfn_t pfnPrepare;
	OnProcessPfn_t pfnProcess;

	void *pArg; // routine 
	bool bTimeout;
};
struct stTimeoutItemLink_t
{
	stTimeoutItem_t *head;
	stTimeoutItem_t *tail;

};
```
最重要的数据结构：
1. 链表结构（prev，next，link）
2. 两个函数，一个参数：prepare, process, arg
3. 超时时间

stCoCond: 等待队列
stCoCondItem: cond的等待对列元素（形成队列有两种方法：1. 类似于tailq那种在timeout中添加属性 2.类似于现在这种另外创建Node的方法

数据结构的操作：

template <class T,class TLink> void RemoveFromLink(T *ap): 
从链表中摘除，同u_queue_delete_link, 比较特殊的是链表是三向链表

template <class TNode,class TLink> void inline AddTail(TLink*apLink,TNode *ap):
将三向链表元素添加到链表尾部，类似于u_queue_push_tail_link

template <class TNode,class TLink> void inline PopHead( TLink*apLink )
从三向链表表头获取元素，u_queue_pop_head_link

template <class TNode,class TLink> void inline Join( TLink*apLink,TLink *apOther )
三向链表concat操作

所以，搞了这么多，也就是链表的基本操作：popHead, AddTail, remove, join，

2. 先cond_signal，后cond_wait会不会丢失signal： 会丢失signal，但是用法上就不应该用signal计数，应该用taskqueue来计数

3. 所以说cond和epfd是两个调度单位喽: 是的，实际上每一个cond实例都是一个调度单位，因此是ncv + epfd个调度单位

4. 会不会出现死锁： 因为在同一时刻，可能出现所有co都在等待cv，所以可能会出现死锁！但是，同线程类似，这并不能
说明cond基础设施有问题，只能说明我们在使用cond的时候需要通过设计避免此类问题。

5. 需要注意的是，signal操作并不是直接swapto(co), 而是将co添加到调度器就绪队列中！



---- 分析调度器的行为

分析来看，yield操作，
co_yield: swap to prev
co_yield_env: swap to prev
co_yield_ct: swap to prev

1. 是不是都是yield to dispatcher 模式？ 从分析上来看应该是yield to prev模式！

2. callstack是什么鬼？ co调用栈，co_resume压栈，co_yield*弹栈；
弹栈之后co不在callstack中，这是没有关系的。因为弹栈意味着要么
co已经不会在运行了，或者co已经加入到别的等待队列中了！


---- 分析epoll调度器

socket
bind
listen
accept
recv/read/recvfrom/recvmsg
send/write/sentdo/sendmsg
close

connect


预期调度策略如下：
```
if api(fd) would block:
    create mapping: fd <-> co
    epoll_ctl(add fd)             // which event
    yield
```

基于epoll的调度:

```
epoll_wait(epfd, events, fds)
    foreach fd in fds:
        swapto(fd<->co)         // really? everytime?
```

0. 支持的api包括哪些，包不包括read/write
1. epfd 是不是只有enable_sys_hook的情况下才有必要存在，如果不是，其他的用途是啥？ NONONO, epfd在任何情况下都存在！
2. epfd 管理的event有哪些种类？
3. 除了网络事件以外的情况怎么调度？
4. 如何设计其他应用场景的调度器（通用场景，数据库场景）？
5. 是不是只支持TCP，能不能支持UDP，有没有必要支持UDP?
6. co_resume与co_swap的区别在哪里？啥时候resume，啥时候co_swap？在cond切换的过程中是不是使用了co_swap
7. 协程的调度器是否可抢占？为什么会有多个icallstacksize
8.




数据结构：

```
struct stCoEpoll_t
{
	int iEpollFd;
    // 最大支持10K event
	static const int _EPOLL_SIZE = 1024 * 10;
    //关于超时？
	struct stTimeout_t *pTimeout;
    //超时队列
	struct stTimeoutItemLink_t *pstTimeoutList;
    //就绪队列
	struct stTimeoutItemLink_t *pstActiveList;
    //保存epoll结果？whatfor？why bother save?
	co_epoll_res *result;

};

struct co_epoll_res
{
	int size;
	struct epoll_event *events;
	struct kevent *eventlist;
};

struct stTimeoutItemLink_t;
struct stTimeoutItem_t
{

	enum
	{
		eMaxTimeout = 40 * 1000 //40s
	};
	stTimeoutItem_t *pPrev;
	stTimeoutItem_t *pNext;
	stTimeoutItemLink_t *pLink;

	unsigned long long ullExpireTime;

	OnPreparePfn_t pfnPrepare;
	OnProcessPfn_t pfnProcess;

	void *pArg; // routine 
	bool bTimeout;
};
struct stTimeout_t
{
	stTimeoutItemLink_t *pItems;
	int iItemSize;

	unsigned long long ullStart;
	long long llStartIdx;
};

struct stPoll_t : public stTimeoutItem_t 
{
	struct pollfd *fds;
	nfds_t nfds; // typedef unsigned long int nfds_t;

	stPollItem_t *pPollItems;

	int iAllEventDetach;

	int iEpollFd;

	int iRaiseCnt;


};

struct stPollItem_t : public stTimeoutItem_t
{
	struct pollfd *pSelf;
	stPoll_t *pPoll;

	struct epoll_event stEvent;
};

```

eventloop的逻辑：
epoll_wait events
foreach e in events:
   prepare OR
   add e to active
takeAlltimeout
join active, timeout

foreach a in active:
    if a timeouted:
        addTimeout(a)

    if process
        procss(a)


对于cond, epoll event来讲，poll都是切换到对应的coroutine运行

timeout对应的pfnProcess是什么？
AddTimeout又是什么鬼

思考来看：timeout之后应该切换到对应的协程，让协程进行相应的后续处理
pfn应该也是co_resume

我靠，对于超时的控制我也是醉了！

分析下来思路竟然是：
1ms per loop:
    将所有Timeouted的co全部拿出来，然后检查是不是真的timeout(因为timeoutarray大小有限，有些item并没真的timetout）：
    如果真的timeout，执行pfnProcess（也就是co_resume）；如果没有timeout则重新加回到timeout列表中！

综上：timeout的控制策略有待改进，可以和libevent以及twemproxy类似地，用平衡树维护


pPoll是什么鬼? 
什么东西需要prepare？为什么prepare，为什么prepare策略是那个样子的？
所有网络网络IO引发的poll

基于epoll的调度器怎么着处理其他的非网络程序的调度?

啥时候 co 退出？ yield？ 如果co执行结束了，是不是会退出调度，释放内存？

read结束了之后，libco是如何让co退出epoll的？要不然会出现错误的事件触发


poll与epoll重要区别：

poll和select一样是一次性的！
epoll则不一样，如果不将fd 删除则一直在epoll中！
虽然libco中不hook epoll的原因是：
一个线程一个epoll就好！
如果epoll的话，也就没有必要coro了


------------------
TODO

1. 分析体会example, 共享堆栈
2. 整理libco的设计思路，实现关键点等材料，以供upsql-proxy选型
3. 制定携程的推进计划（分享，选型，试点，改进与定制等）

NTOE: 如果利用libco的话，有一个非常重要的问题是！如何移植到AIX平台上？因为现在这种通过保存x86寄存器的行为是不可行的
power架构的寄存器可能没有办法获得！
或许还能成为一个特性！

-----------------
其他coro模型的调研：

1. cloudwu/coroutine: 
    共享栈（cow），ucontext，用户调度（功能非常简洁，用来展示ucontext的用法还是不错的）
2. libgo: 从宣传来讲的话，和libco的思想不一样，和goroutine是很接近；
有协程池，channel，mutex概念；
调度算法和goroutine也是比较接近！
利用多线程, 可以尽量避免libco中的多线程&多协程；多进程多协程的编程模型, 感觉上更加promising
另外可以将hiredis，mysql-client这样的同步库集成到协程模型中，阴吹斯汀

从代码来讲，作者比较有合作精神，文档尽量详细。
但是代码使用了大量的c++的高级语言特性，不太容易看明白。



3. boost.aio


4. lthread

文档：
http://lthread.readthedocs.io/en/latest/intro.html
* 汇编swap
* 添加了耗时的计算操作支持
* 协程独享栈，madvise节省空间
* 万-百万量级协程
* 每个线程都有一个scheduler，可以充分利用多核优势
* lthread考虑了磁盘IO的处理（通过后台线程进行处理）


问题：
* coro挂起/恢复时是否需要拷贝栈空间
* 怎么在几个队列和rbtree中进行状态流转的
* disk io 线程怎么通知已经完成了指定的diskio任务，diskio任务如果失败了怎么办？
* 多个线程中的协程需不需要做协程的数据同步，怎么做？
* 能不能考虑采用libaio来进行相应的diskio的调度


缺点：
* lthread为什么不对系统函数进行hook？这样的话移植的难度增大!
* 现在所有的协程组件都没有对ppc进行支持，这个可能是一个创新点?
* 现在采用的后台线程进行disk IO的方案是否合理？
* 受制于stackfull模型，该方案协程数量只能到万!
* 受限于yield to scheduler的模型，lthread的切换效率比libco要小不少(1/2)

总结：
* 从代码的实现优雅程度来讲，还是不如libio的，但可以肯定的libco从其中获取了一些灵感
* lthread尝试解决的几个问题在实际的使用中应该是有的，但是需要看看有没有更加完美的解决方法
    1. 如果协程的逻辑中含有比较耗费CPU的操作怎么办?是不是会starve掉某些协程！
    2. diskIO怎么办，难道不考虑了？


--------
分析,可能引起状态变化的操作
主动:
new
exit
join
detach
yield
cancel
resume

被动
timeout(expired)
cond
diskio
socketio
compute


1.libco的效率，少量fd与libevent相比性能损失5%
2.大量fd的实验
3. libco的默认读写超时时间为1s，这个与正常的同步读写的行为不一致！

单线程8字节，客户端一发一收，svr一收一发，proxy传递消息，
将proxy的CPU使用压到100%(此时svr，cli的cpu使用率大致为60%)，TPS:

| 链接数量 | 2      | 4      | 8      | 16     | 32     | 64     | 128    | 256    | 512   | 1024  |
| libco    | 98562  | 101414 | 103259 | 101640 | 104710 | 101104 | 102009 | 95785  | 71460 | 61724 |
| event    | 105979 | 111234 | 115291 | 116121 | 115314 | 119380 | 118892 | 113697 | 87522 | 75591 |
| 性能损失 | 7%     | 9%     | 10%    | 12%    | 9%     | 15%    | 14%    | 16%    | 18%   | 18%   |


综上所述，在使用libco之后，性能大致损失10-20%；
链接数量越少，损失的性能越少.

另外在libco

# libco 

2016.10 ~ 2017-10

tencent opensource coroutine lib.

## usage

## conventions

## design


## detals

## TODO

- use libevent to speed up libco
- libco on database API ? like c# await ?
- libco is now tightly couple with pEpoll, what if we are not writing a non network program.
- dig c# await, c++ boost, wikipedia mentioned implementation for imagination

## questions

- env callstack is 128-dimensional array, what happens if more coroutine is 128 level
- enable_sys_hook in co or main?
- have to bear in mind that co may yield at any IO operation, and have to know from when the io may yield

- 在使用多进程accept的架构中，如果使用libco则需要在fork之前SetNonblock？
- 对于fd和filetable以及fork的理解还不够深入!
- 需要仔细观察在 enable_hook_sys之前和之后 使用网络API的差别; 在enablehooksys之前，创建的fd都是阻塞的，而且也没有办法在加入到eventpoll中来
所以 enablehooksys的时机是需要比较考究的！

- 在proxy的实现中就出现如下问题：
listenfd需要在fork前创建, 且listenfd需要在enable_hook_sys（否则accept会阻塞整个进程）
pre_connect需要在fork后创建（否则后端连接的offset将混乱），但是希望此时没有enable_hook_sys（因为此时不希望connect非阻塞）
所以这个地方出现了一个比较尴尬的地方

- enable_hook_sys在必须在co_create之后才会有效(主协程中需要co_create(dummy)之后才会enable_hook_sys生效)

------------
使用libco，大约两百行就可以写一个proxy:
1. 除去多进程负载均衡 主协程enablehook的不方便之外，libco总体上还是用法简单的
2. 更加直接的想法是： 主协程负责accept->co_create&co_resume->read/write-> co_return

关于性能的对比：目前来看，co实现的echo_svr, echo_cli能够实现20wtps/co; echo_proxy能实现9wtps/co

使用libevent实现
---------

- gcc -l order matters
- ev_persist的情况下，如果链路出现异常会怎样, 我们需要怎么做？
::直接delete event就好 

- 编写svr需要考虑的问题：
1. 读取请求之后，如何进行回复？（因为可能大量事件fd都writable，如果使用PERSIST写事件busy-polling, 耗费的cpu过多；因为可能读写极有可能在同一个线程，那么使用pthread_cond进行同步也是不可行的；)
2. 如何处理读写平衡?（因为读写在速率上可能不匹配，那么需要缓存请求；另外如果读速率长时间大于写速率，那么有可能撑爆缓存; 既然需要缓存请求，那么就必然会牵扯到内存管理的问题）
3. 关于libevent使用上的疑问： 同一个fd，有两个ev，一个读一个写是否可行？ 同一个fd，多个读事件evr1,evr2, ...；同一个fd有多个写事件evw1，evw2，...；fd与ev之间的疑问！
::猜想应该是读事件触发，则注册了读事件的都被执行，写事件同理
4. 将同一个事件ev，添加到epoll中N次，并且cb中不重新添加ev，那么事件触发之后会出现什么情况：A. cb触发一次 B. cb触发N次， C. 其他


--------------
TODO
twemproxy的内部细节还是没有特别清晰啊！
比如说没有意识到之前的读写分离之后的读怎么通知写的!



# libeco

基于libevent的协程库, 与libevent兼容，可以同事使用callback和eco。

由eco, channel, socket api三部分组成。

- eco       : 非对称，stackfull协程原语
- channel   : 线程安全的协程通信机制
- socket api: 适应eco的socket api函数

## API

参考 [eco.h](http://172.17.249.122/srzhao/libeco/blob/master/eco.h)

## tutorial


参考 [sample](http://172.17.249.122/srzhao/libeco/blob/master/sample)


## 协程设计

### eco

asymmetric stackfull coroutine.

#### 特点

- yield to caller
:: 更加符合常规（return返回caller，yield返回caller）
:: 与stackless的协程处理方式靠近
- 不可以递归调用(即不能co_resume(co_self()))
:: 如果递归调用，co的ctx会被覆盖
- eco_join与pthread_join语义类似：等待co DONE，后释放co资源


#### 详细设计

![eco](eco.PNG)

- co不能跨线程执行（即线程与co是一对多的关系）
:: 考虑过eco操作都带eco_env参数，但API使用起来比较麻烦
所以目前线程有一个私有的eco_env

- eco_setup用于创建并初始化线程相关的数据
:: eco_setup用于穿件当前线程的执行环境--eco_env, 包括指定event_base,
创建callstack。

- 协程含有五种状态：INIT，ACTIVE，PENDING，STACKED，DONE
:: co_create 创建的co处于INIT
:: co_resume 当前co转为STACKED，目标co转为ACTIVE
:: co_yield  当前co转为PENDING，父co转为ACTIVE


### channel

- 与goroutine的channel类似：buffer满，send阻塞；buffer空，recv阻塞。
- 线程安全
- recv/send阻塞（co），但不会阻塞线程

#### 详细设计

- 通过eco_env相关的pipe+event进行注册和通知
- 消息按照FIFO格式进行存取

实现逻辑参考 [eco_chan.c](http://172.17.249.122/srzhao/libeco/tree/master/eco_chan.c)

### socket api

- 同步逻辑，异步执行
- 单个fd可以在多个co中使用
- 只能使用nonblock的fd

#### 详细设计

基本思路是：在EAGAIN时，注册事件并yield。当r/w事件发生时，resume
之前yield的co，从yield点继续执行。

由于libevent等事件库不支持一个fd上绑定多个事件（也没有意义），但是由于
协程中多个co共享一个fd的情况比较普遍（比如proxy：多个前段链接公用有限
的后端链接）,因此需要支持这种用法。


通过在每个fd关联一个阻塞的co队列实现公用fd。具体逻辑参考
[eco_socket.c](http://172.17.249.122/srzhao/libeco/tree/master/eco_chan.c)

## TODO

- 完善libeco（API补充，测试）
- 兼容libev，libuv事件库
- 提供简单的事件库实现
- 研究并提供stackless的协程库



--- 
问题列表

1. socket中如何处理EINTR，为什么会出现EINTR，poll中

--------

两个决定：

1. 能否不依赖与libevent的超时事件？
- libev和libuv可能没有带超时的事件
- 带超时的事件是否比超时+事件性能更好还不一定
- eco_poll多个(事件+超时)处理起来貌似比多个事件+超时更加不优雅

最终决定： 采用单个超时+多个事件

2. 支持读写分离?
pros
- 性能更好?
cons
- 模型更加复杂
- API更加复杂，不太好设计
- 实现起来貌似也不够优雅
- 能够应用到读写分离的场景比较少吧！

决定：暂时读写不分离，先把基本的逻辑弄稳定，然后在具体场景测试两种方案性能对比








