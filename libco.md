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

