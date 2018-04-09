
#9 fix mvn test fail

mvn test与make test执行的命令不一样！

make test执行的是TestRunner

mvn test:
- Test Runner为插件maven-surefire-plugin
- maven-surefire-plugin的test目标会自动执行测试源码路径（默认为src/test/java/）下所有符合一组命名模式的测试类。这组模式为：
**/Test*.java：任何子目录下所有命名以Test开关的Java类。
**/*Test.java：任何子目录下所有命名以Test结尾的Java类。
**/*TestCase.java：任何子目录下所有命名以TestCase结尾的Java类
- 跳过测试 mvn package -DskipTests  
- 选择特定的测试案例 mvn -Dtest=TestSquare,TestCi*le test

我的问题出在maven默认的行为不能共享BaseTest代码，解决办法：
https://stackoverflow.com/questions/174560/sharing-test-code-in-maven#174670

- jedis中基本测试环境搭建是通过Makefile进行，jedis使用Makefile部署/撤销环境，调用mvn

#4 add tutourial

查看jedis，发现jedis并没有在src中添加示例代码
test中示例了一些用法，更多的示例是通过wiki给出的。

#5 机器宕机造成api调用耗时太久

解决方法：
1. 参照clogs的策略，但是需要非阻塞发送ping报文。
2. 启动线程做检测！
3. 搜索java redis 负载均衡


搜集信息：
1. 可能可以通过pipeline来做（作者讲的）！
https://stackoverflow.com/questions/11338936/does-jedis-support-async-operations
刚刚分析了下，使用pipeline依然会阻塞！

2. issue中表示在3.0中会支持async特性，但是目前还没有看到3.0的计划2011-2017 still work in progress....
https://github.com/xetorthio/jedis/issues/241


3. 关于对Jedis做load-balance的工作已经有一个质量很差的实现：
https://github.com/CodingDance/JedisBalance

!!!也是基于线程的实现。

TODO：

- 关于Java的IO非阻塞异步的知识
- Jedis中的其他类的用法深入了解


NIO
We're still studying future vs callback.

Yes. Actually I feel very tricky to implement with RxJava because most of commands returns single value, and there're many kinds of return types.
But I also agree that callback could be hell, and Java Future (under Java 8) is not fully async, so I'll give it a try.

从以上讨论至少了一看到以下信息：
1. jedis尚未支持async特性
2. 实现异步特性至少含有以下方法：
- netty
- vert.x
- rxjava
- future
- callback
- NIO
- lettuce

oh my god! mess like hell

并且我感觉应该不太好做！妈蛋，可能还是要用线程方法！一觉回到解放前


能不能直接利用client的命令，但是getresult?


#7 提供原生jedis服务

既然要提供jedis服务，那么必须了解Jedis原生提供了哪些东西喽!


直接看吧(3-4w)！


Jedis->BinaryJedis + JedisCommands, MultiKeyCommands, AdvancedJedisCommands, ScriptingCommands, BasicCommands, ClusterCommands, SentinelCommands, ModuleCommands 

ctor:
  Jedis(JedisShardInfo shardInfo) 支持分片
  Jedis(URI uri) 支持uri指定服务器信息
  支持ssl


methods:

- 每个命令都会先检测是否pipeline or multi
- 命令基本都是client在执行，Jedis简单地对这些命令进行封装（并返回值）


>> so client does all the hard work


BinaryJedis -> BasicCommands, BinaryJedisCommands, MultiKeyBinaryCommands, AdvancedBinaryJedisCommands, BinaryScriptingCommands, Closeable

ctor:

- 区分了sotimeout和connectiontimeout
- 依然支持shard和uri

variable:
 client
 pipeline
 transaction

methods:

- 依然是client干活
- 与Jedis最大的区别在于输入输出参数都是byte，调用client函数为直接命令而不是sendCommand
- checkIsInMultiOrPipeline的作用是检查当前的jedis模式并抛出异常

>> wow! 代码真他妈多，但是不理解为什么需要BinaryJedis，我们又不使用。


Client -> BinaryClient + Commands:

ctor:

支持ssl，但是URI在BinaryJedis中已经处理过了！

methods:

- 基本都在使用BinaryClient中的方法，但是对参数进行了safeencode
- sendCommand 居然是继承的！

>> 又是个代理商


BinaryClient -> Connection:

ctor:

- 全部代理到Connection中

variable:

  isInMulti 是否在multi模式
  password  密码（重连时会用到）
  db        数据库
  isInWatch watch模式

methods:

- 实现了很多方法，但都调用了sendCommand/sendEvalCommand

>> again 承包商

Connection + Closeable:

ctor:

variable:

private String host = Protocol.DEFAULT_HOST;
private int port = Protocol.DEFAULT_PORT;
private Socket socket;
private RedisOutputStream outputStream;
private RedisInputStream inputStream;
private int connectionTimeout = Protocol.DEFAULT_TIMEOUT;
private int soTimeout = Protocol.DEFAULT_TIMEOUT;
private boolean broken = false;
private boolean ssl;
private SSLSocketFactory sslSocketFactory;
private SSLParameters sslParameters;
private HostnameVerifier hostnameVerifier;

methods

connect: socket连接，准备好inputStream，outputStream
sendCommand: Protocol.sendCommand最后基本是调用的静态方法
getStatusCodeReply: 阻塞读取回复，然后encode

？怎样保证结果已经读取完全, 特别是像pipeline这种使用方式？
Protocol.read怎么进行消息分割的？

>> connection中关于IO操作以及强制类型转换还是不太容易看明白！

Protocol

ctor:

- Protocol不能实例化

variable:

- 大量的默认值，constants

methods:

sendCommand: 按照redis协议组合命令。
read: read并不是trival的inputStream.read，该read表示处理一个回复消息;
read 给根据firstbyte判断回复的类型，然后采取不同的策略读取结果。


- 关于connection中的疑问释然了：
tcp流式数据模型在c/java中没有区别.
byte[]并不能智能地转换为任意类型，而是因为采用了不同的process方法。

>> 比较有趣的是Enum的特性，enum看起来像是对每一个枚举都有一个对象


----------------------------------------
JedisSentinelPool

ctor:

先遍历Sentinels，获取当前masterName集群的master；然后向每个sentinel注册
masterListeners，如果sentinels做出了切换的决定。pool将收到sentinel的切换
通知。

variable:

masterListeners = new HashSet<MasterListener>();

method:

提供getResource, returnBrokenResource, returnResource三个标准的接口


MasterListener -> Thread:
setDaemon
start

ctor:

variable:

method:

run 

订阅sentinel的信息推送，并且如果exception之后，sleep 5s再次尝试订阅

如果出现failover，会重新initPool

所以这个引入了PubSub这一特性！


>> 虽然sentinelPool能够做到failover，但是依然不能对多个pool进行管理。

ShardJedis -> BinaryShardedJedis + JedisCommands, Closeable :


我擦不能这么分析，后面的复杂。

- 如何做到一致性哈希的？
- 如何做到多线程安全的？因为存在多个线程同时哈希到一个Jedis，然后同时发送?
- 与SharedJedisPool的区别?

貌似每个shard都有一个对应的Jedis，然后呢shardedJedis与Jedis一样，并不是
线程安全的；但是对于单线程而言，SharedJedis聚合了多个Jedis，然后分片，单线程
不会同时访问同一个Jedis，因此不存在多线程问题。

>> 总而言之是采用了一致性哈希来将多个key分配到多个jedis中。

SharedJedisPipeline：

>> 横向扩展Jedis并且使用其Pipeline功能。

ShardedJedisPool -> Pool<ShardedJedis> 

ctor:

variable:

method:

SharedJedis的池


---------------------
至此，Jedis的代码粗略分析完成。

问题1： 能不能通过JedisBalancer直接链接redis？

暂不支持！但是可以采用SharedJedisPool

问题2： 能不能组合SharedJedisSentinelPool? 提供一个分片的主从JedisPool？

fair enough！

但是按照钱包的实现思路实现就可以了！

------------------------

回到最开始的问题：能不能非阻塞发送Jedis报文？

java的非阻塞编程与C的模型一样；但是Jedis本身并不支持，所以即使能够通过socket非阻塞发送

开个线程喽！


---------------------

方案：

1. 开启一个线程做recover & isolate
2. getResource不做recover isolate



----------------------
关于pom中的依赖问题：







