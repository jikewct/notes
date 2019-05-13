
# http协议

http/1.1的协议为一请求一应答模型，可能产生队头阻塞问题；而http/2.0采用了
multiplexing的方法（类似于magpie？）。

verb: GET/POST/DELETE等

keepalive: server在应答之后不断开链接（必须有content-length字段）

pipeline: client在收到应答之前发起下一个请求（server必须支持keepalive)

chunked: content-length的另一种表示，chunk为0表示该请求完成

cookie: 服务端设置的，客户端每个请求都带上的附加数据（状态从server转嫁到client）

# restful

'Representational State Transfer'

API设计遵守 动词(verb) + 名词(endpoint) + 形容词(过滤) 的规范。

# evhttp

- 一个evhttp可以bind多个addr，但是包括该http涉及的所有fd（包括listenfd, acceptedfd)只能使用一个base，这也使得一个addr最多只能达到2-3万TPS
- 其他参考test

# curl

## easy

同步接口

## multi

多路复用接口，大体有curl_multi_perform和curl_multi_socket_action两种用法。

### `curl_multi_perform`

### `curl_multi_socket_action`

设计思路一句话描述就是：

在socket_cb中告知应用需要poll哪些fd的啥事件，在timer_cb中告知需要添加的超时时间。
从而让应用可以利用事件框架将整个应用驱动起来。

设计思路上和mysql的异步客户端类似，但是和redis的异步客户端设计相差较远。

主要的cb:

CURLMOPT_SOCKETFUNCTION : 

callback functions that libcurl will call with information about what sockets to 
wait for, and for what activity, and what the current timeout time is.

CURLMOPT_TIMERFUNCTION

# MHD



