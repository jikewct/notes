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

<arpa/inet.h>
int inet_aton(const char *str, struct in_addr *addr); //返回bool
in_addr_t inet_addr(const char *str); //如果无效返回INADDR_NONE,INADDR_NONE为255.255.255.255为广播地址（该函数被废弃）
char *inet_ntoa(struct in_addr inaddr); //返回值为静态内存，该函数不可重入

int inet_pton(int family, const char *str, void *addr);//1-正常；0-无效；-1出错
const char *inet_ntop(int family, const void *addr, char *str, size_t len);//
<netinet/in.h>
#define INET_ADDRSTRLEN 16
#define INET6_ADDRSTRLEN 46


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

* 抓包
tcpdump

