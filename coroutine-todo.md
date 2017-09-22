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











