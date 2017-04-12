# udp

udp无连接，不可靠。

典型应用：DNS, NFS, SNMP

基本的API包括

#include <sys/socket.h>

ssize_t recvfrom(int sd, void *buff, size_t nbytes, int flags,
    struct sockaddr *from, socklent_t *addrlen);

ssize_t sendto(int sd, const void *buff, size_t nbytes, int flags,
    const struct sockaddr *to, sockelen_t addrlen);

NOTE:
- UDP可以写一个报文长度为0的报文。

## misc

- 已连接udp套接字

对于已连接udp套接字与默认的未连接udp套接字相比：
1. 不能指定目的地址:不能使用sendto，必须使用send或者write
（其实也可以使用sendto函数, 但是不能指定目的地址）

2.不必使用recvfrom获取源地址（因为内核只返回只有connect指定地址的数据包）

3. UDP套接字引发的一步错误会返回给他们所在的进程

4. 已连接套接字比未连接套接字的效率更高


