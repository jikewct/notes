# 网络编程

* 套接字

IPV4 套接字

<netinet/in.h>

struct in_addr {
    in_addr_t       s_addr;
}

struct sockaddr_in {
    uint8_t         sin_len;
    sa_family_t     sin_family;
    in_port_t       sin_port;
    
    struct in_addr  sin_addr;
    
    char            sin_zero[8];
}

通用套接字

<sys/socket.h>

struct sockaddr {
    uint8_t         sa_len;
    sa_family_t     sa_family;
    char            sa_data[14];
}

IPV6套接字
<netinet/in.h>

struct in6_addr {
    uint8_t         s6_addr[16];
}

#define SIN6_LEN 

struct sockaddr_in6 {
    uint8_t         sin6_len;
    sa_family_t     sin6_family;
    in_port_t       sin6_port;

    uint32_t        sin6_flowinfo;
    struct in6_addr sin6_addr;

    uint32_t        sin6_scope_id;
}

* 字节序

网络字节序为小端

<netinet/in.h>
uint16_t htons(uint16_t host16bitvalue);
uint32_t htonl(uint32_t host32bitvalue);
uint16_t ntohs(uint16_t net16bitvalue);
uint32_t ntohl(uint32_t net32bitvalue);


* 地址转换

命名含义：

```
n -- in_addr
a -- 点分十进制字符串地址
p -- in4/6_addr
```


```
<arpa/inet.h>

int inet_aton(const char *str, struct in_addr *addr); //返回bool
in_addr_t inet_addr(const char *str); //如果无效返回INADDR_NONE,INADDR_NONE为255.255.255.255为广播地址（该函数被废弃）
char *inet_ntoa(struct in_addr inaddr); //返回值为静态内存，该函数不可重入

int inet_pton(int family, const char *str, void *addr);//1-正常；0-无效；-1出错
const char *inet_ntop(int family, const void *addr, char *str, size_t len);//
<netinet/in.h>
#define INET_ADDRSTRLEN 16
#define INET6_ADDRSTRLEN 46
```


* getaddrinfo

network, service地址操作。

```
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>

int getaddrinfo(const char *node, const char *service,
        const struct addrinfo *hints,
        struct addrinfo **res);

void freeaddrinfo(struct addrinfo *res);

const char *gai_strerror(int errcode);

struct addrinfo {
    int              ai_flags;
    int              ai_family;
    int              ai_socktype;
    int              ai_protocol;
    socklen_t        ai_addrlen;
    struct sockaddr *ai_addr;
    char            *ai_canonname;
    struct addrinfo *ai_next;
};


node：

a) 点分十进制网络标记，ipv6标记；
b) hostname（将执行DNS检索）

如果flags指定了AI_NUMERICHOST，那么node必须是a)格式

如果flags指定了AI_PASSIVE且node为null，则返回的结果可用于bind；如果node不是null，则AI_PASSIVE将被忽略

如果没有指定AI_PASSIVE，那么返回结果适合可用于connect，sendto，sendmsg，如果node为null那么返回的是loopback地址；

如果指定了AI_ADDRCONFIG，那么返回结果将不包含loopback地址。

service:

a) 数字端口
b) 服务名services(6)
    
如果service为null，那么最终得到的端口是未初始化的。

如果flags指定了AI_NUMERICSERV，那么service必须是a)格式，该标记用于禁止（DNS检索）


node 与 service最多只能有一个为NULL。


getaddrinfo 返回符合过滤条件的链式addrinfo，通过freeaddrinfo释放。getaddrinfo的排序
根据RFC3484确定。

```

* getifaddrs

枚举本机网卡和ip地址。

```
#include <sys/types.h>
#include <ifaddrs.h>

int getifaddrs(struct ifaddrs **ifap);

void freeifaddrs(struct ifaddrs *ifa);

struct ifaddrs {
    struct ifaddrs  *ifa_next;    /* Next item in list */
    char            *ifa_name;    /* Name of interface */
    unsigned int     ifa_flags;   /* Flags from SIOCGIFFLAGS */
    struct sockaddr *ifa_addr;    /* Address of interface */
    struct sockaddr *ifa_netmask; /* Netmask of interface */
    union {
        struct sockaddr *ifu_broadaddr;
        /* Broadcast address of interface */
        struct sockaddr *ifu_dstaddr;
        /* Point-to-point destination address */
    } ifa_ifu;
#define              ifa_broadaddr ifa_ifu.ifu_broadaddr
#define              ifa_dstaddr   ifa_ifu.ifu_dstaddr
    void            *ifa_data;    /* Address-specific data */
};

```

* getsockname getpeername

获取fd对应的四元组地址。

```
int getsockname(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
int getpeername(int sockfd, struct sockaddr *addr, socklen_t *addrlen); 
```

* 关于select poll epoll

材料：
https://daniel.haxx.se/docs/poll-vs-select.html(libcurl作者的比较）
Comparing and Evaluating epoll, select, and poll Event Mechanisms(65, 2004 ols2004)
http://stackoverflow.com/questions/4093185/whats-the-difference-between-epoll-poll-threadpool 199
http://stackoverflow.com/questions/17355593/why-is-epoll-faster-than-select 58
http://stackoverflow.com/questions/4039832/select-vs-poll-vs-epoll 32
man page http://man7.org/linux/man-pages/man2/select.2.html
apue
unp

库；
libev，libevent, libuv

应用：
twemproxy
redis
memcached
libcurl
axel

# 进程



```
execve
---
#include <unistd.h>

int execve(const char *filename, char *const argv[],
        char *const envp[]);

execl
---
#include <unistd.h>

extern char **environ;

int execl(const char *path, const char *arg, ...);
int execlp(const char *file, const char *arg, ...);
int execle(const char *path, const char *arg,
        ..., char * const envp[]);
int execv(const char *path, char *const argv[]);
int execvp(const char *file, char *const argv[]);
int execvpe(const char *file, char *const argv[],
        char *const envp[]);

```


* 抓包

tcpdump
=======


* 抓包 tcpdump tcpdump -i eno1 -XX host 172.20.51.159

* 发送

* nc

* 非阻塞 connect， close， shutdown， accept
connect: 立即返回EINPROGRESS，三步握手继续进行；值得注意的是如果是在C/S在同一个机器，那么通常立即返回，而不是EINPROGRES。

tools
http://stackoverflow.com/questions/4777042/can-i-use-tcpdump-to-get-http-requests-response-header-and-response-body
wireshark for capturing http request
tcp [like wireshark but command line]
http debug proxy charles and fiddler
firebug let you see the parsed request
telnet netcat socat connect directly to 80, and mannualy construct request
htty help construct a request and inspect the response

关于链路状态的保持：
- 链路出错了怎么办？链路随时出错怎么办？
- EINTER? EINPROGRESS? EPOLLERR? EPOLLHUP?
- connect, close, accept与非阻塞
- twemproxy如何做到auto-eject？（也就是服务端自动隔离）


twemproxy的链路操作总结：
1. EPOLLERR, : 
   epoll删除fd资源
   对于proxy，直接close
   对于server, 直接close并且释放相应的msg资源；但是并不会立即剔除svr；下次再来请求还是会
               进行connect
   对于client, 直接清除资源，close

2. server_connect: 
    socket
    set_nonblock
    event_addcon
    connect（一般这个时候，都是EINPROGRESS）
    成功之后，epoll, select, poll会有写事件！(make sense)




-----
about close/shutdown/FIN/reset

shutdown SHUT_RD, the kernel protocol stack really send no (FIN) packets!!

- shutdown SHUT_RD, will cause block recv to return 0 (logically closed by peer, but discards ongoing msg). 
  on linux, we could still recv from peer, but would not block; on windows or AIX, behavior is 
  different; 
  to summarize the behavior: recv would return 0 instantly, and we should not recv from the connection from now on.

- connect, start the 3-way handshake (processed by tcp/ip stack)
- accept, get on connection from backlog, block if none (FIN+ACK is not triggered by connect)

- shut_r: local recv return 0; remote can still send
- shut_w: local send got sigpipe; remote recv return 0
- close: sigpipe on local and peer; unlike connect, usually close return immediately (while closing in backgroud by kernel) unless so_linger set


-----
for non-blocking network io

- connect: E_INPROGRESS, EAGAIN(no avaliable port)
- close: 
- accept: EAGAIN, ENOFILE, EMFILE
- read, recv, recvfrom, recvmsg: EAGAIN
- write, send, sendmsg, writev: EAGAIN

connect & close normall would not block, cause kernel tcp/ip stack run in backgroud




------------------
connect 超时:
    - linux 3.10内核，受setsockopt的影响
    - AIX 不受setsockopt的影响，75s超时

accept  超时:
    - linux 3.10内核，受setsockopt影响
    - AIX 不受setsockopt的影响，不超时

posix没有明确表达过以上行为，因此

----------------
关于EINTR的意义：
是不是有可能在写数据的过程中出现EINTR？即write返回ret < requested?

---------------
getaddrinfo


# 代理

## socks

## http

# port forwarding

# ss

# privoxy

# nginx






