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
