<<<<<<< HEAD
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

