# coreutils

GNU提供的一系列常用工具组件，包含了fileutils, sh-utils, textutils。

coreutils是linux系统的基础工具，在所有nix系统都安装了。

## coreutils场景与案例

### sh-utils

- vim sudo写文件

```
:w !sudo tee %
```

- 如何后台运行？

nohup <command> &

nohup忽略terminal退出时向子进程发送的SIGHUP信号, 使得进程在terminal关闭
之后退出。

在很久以前，UNIX通过拨号上网连接到主机上，因此当terminal主动挂机之后，
该terminal的子进程应该通过SIGHUP被终止。

除了nohup，terminal multiplexer也可以达到类似的效果。

- 模拟CPU繁忙

```
yes >/dev/null &
```

- 保存日志的同时查看日志
```
<command> >log 2>&1 ;tail -f log
<command> 2>&1 | tee log
```

- 环境变量

a) shell环境变量
```
printenv
env
```

b) 进程环境变量
```
strings -a /proc/<pid>/environ
```
NOTE: /proc/<pid>/environ显示的是进程初始化环境变量，实时环境变量只能通过gdb
attach到进程之后查看。

### textutils
- vim 读取man文档

```
:r !man fold | fold -s
```

- 从upos-beta到upos-rc1变更了那些包?
```
ls ./upos-beta/Packages > beta
ls ./upos-rc1/Packages > rc1

comm -3 beta rc1
```

### file-utils

- 谁把硬盘用完了？

a) 确认磁盘使用情况

```
df -h /home
```
b) 按使用量排序
```
$ du -sh /home/* | sort -h
```

- problems with *
``  
cp -a 
```

- 怎么安全地删除一个文件夹
```
unlink, 软连接，硬链接
```
- move all up a directory


- 如何当前脚本的所在文件夹绝对路径
```
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#### wrong (or not portable) below ###
DIR=$( dirname $1 ) #source xxx 或者 . xxx时，$0为-bash
DIR=$( dirname ${BASH_SOURCE[0]} ) #dirname得到可能是相对路径
DIR=$( dirname $( realpath ${BASH_SOURCE[0]} ) ) #realpath在SUSE等发行版中没有
DIR=$( dirname $(readlink -f ${BASH_SOURCE[0]} ) ) #另外如果脚本名称含有空格(如：\ xx\ yy)，得到的是错误结果
DIR="$( dirname "$(readlink -f "${BASH_SOURCE[0]}" )" )"  #如果脚本为软链接，得到的是链接指向的脚本所在目录
```
参考：http://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within


- 文件传输有没有出错？

a) 生成MD5sum
```
$ md5sum  * > md5sum.txt
```
b) 验证
```
$ md5sum  -c md5sum.txt
```

- 刻录启动盘
```
dd if=upos-rc1.iso of=/dev/sdx
```

- 粉碎*密文件
```
shred /path/to/secret
```

- 清除磁盘缓存
```
sync; echo 3 > /proc/sys/vm/drop_caches
```


### misc

- 为啥不能sudo cd?

由于current working directory为当前进程的属性，而shell通过创建

- 为啥不能随意删除tmp目录下的文件
```
drwxrwxrwt.  13 root root       4096 May 15 20:49 tmp/
```
由于/tmp文件夹为 set-stiky目录，该目录下的文件只有 该文件夹owner、文件owner、root
能够删除该文件。

- 为啥普通用户能修改passwd
```
-rw-r--r--. 1 root root 4468 Mar  3 16:26 /etc/passwd
-rwsr-xr-x. 1 root root 27832 Jun 10  2014 /usr/bin/passwd*
```
由于passwd为setsid程序，程序启动之后euid为root, 因此能够修改 /etc/passwd。

- why ^H?

- vim加入当前时间

```
:r !date +%F
```
登陆的时候做了些啥？
自定义terminal的类型
自定义LS颜色
自定义PS1的颜色
ANSI color和tty
编辑器的原理
termianl的历史

printf echo 实验terminal特性。

review 扩缩容工具
make.sh
clogs中的make-jemalloc.sh

logname vs whoami vs id

### summarize

yes         yes >/dev/null &
wc          find ./src -name *.c | xargs wc -L | sort -n
timeout     timeout 1s yes
tee         :w !sudo tee %
sync        sync; echo 3 > /proc/sys/vm/drop_caches
stty        stty erase ^H
tail        tail -f log
shred       shred secret.md
dd          dd if=upos-rc1.iso of=/dev/sdx
fold        :r !man fold | fold -s
ln          :ln -s /home/log /var/log

## coreutils命令概述

1. sh-utils
1.1 condition
true
false
test

1.2 print
echo
printf

1.3 Redirection
tee

1.4 environ
env
printenv

1.5 misc
seq
expr
sleep
timeout
kill
yes
nohup

2. fileutils:
2.1 filename 
basename
dirname
pwd
readlink
realpath
pathchk

2.2 file 
cp
install
link
ln
mkdir
mkfifo
mknod
mktemp
mv
rmdir
rm
shred
truncate
unlink

2.3 file attribute
chgrp
chmod
chown
touch
stat

2.4 file listing
dircolors
dir
ls

2.5 file checksum
sha1sum
sha256sum
sum
md5sum
cksum

3. textutils:
3.1 field
cut
paste
join

3.2 output parts of file
csplit
split
head
tail

3.3 sort
sort
uniq
shuf
comm

3.2 output entire file
cat
tac
od
wc
base64

3.3 format
fmt
fold
pr
nl

4. misc:

4.1 hardware
arch
nproc
uname

4.2 disk
sync
dd
df
du

4.5 terminal
tty
stty
stdbuf

4.4 users
id
groups
logname
users
whoami
who

4.3 misc
chroot
date
uptime
hostid
hostname
nice
factor
tsort
