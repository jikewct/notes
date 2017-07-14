cve-2017-1000367

======
2017-06-05

暂时没有找到poc代码，github上有一个cve-2017-100367的仓库
但是暂时not working。代码作者的意见是等官方(openwall)放出
Linux_sudo_CVE-2017-1000367.c

试图理解该cve？

从官方cve描述上看：

1. get_process_ttyname从/proc/<pid>/stat的第7域获取tty_nr
（tty的major，minor device number）但是由于stat第二域comm
可能含有空格，所以，第七域就会变成invalid值, 在/dev/pts中
找不到；因而执行fallback：sudo_ttyname_scan

2. sudo_ttyname_scan 对/dev执行BFS扫描。但是由于/dev/shm是
对所有人可写的，因此可以利用该文件夹制造漏洞

Last, we exploit this function during its traversal of the
world-writable "/dev/shm": through this vulnerability, a local user can
pretend that his tty is any character device on the filesystem, and
after two race conditions, he can pretend that his tty is any file on
the filesystem.

On an SELinux-enabled system, if a user is Sudoer for a command that
does not grant him full root privileges, he can overwrite any file on
the filesystem (including root-owned files) with his command's output,
because relabel_tty() (in src/selinux.c) calls open(O_RDWR|O_NONBLOCK)
on his tty and dup2()s it to the command's stdin, stdout, and stderr.
This allows any Sudoer user to obtain full root privileges.

以上没看太明白

main->get_user_info->get_process_ttyname(parse field 7, 
which could be corrupted)->sudo_ttyname_dev(fallback to scan, if needed)
->sudo_ttyname_scan(BFS scan in /dev and /dev/shm is world-writable)

sudo_ttyname_scan:
bfs遍历
找到字符设备，并且设备号与rdev相同的文件，将文件名作为tty名称。

攻击方法：

========================================================================
Exploitation
========================================================================

To exploit this vulnerability, we:

- create a directory "/dev/shm/_tmp" (to work around
        /proc/sys/fs/protected_symlinks), and a symlink "/dev/shm/_tmp/_tty"
to a non-existent pty "/dev/pts/57", whose device number is 34873;

- run Sudo through a symlink "/dev/shm/_tmp/     34873 " that spoofs the
device number of this non-existent pty;

- set the flag CD_RBAC_ENABLED through the command-line option "-r role"
(where "role" can be our current role, for example "unconfined_r");

- monitor our directory "/dev/shm/_tmp" (for an IN_OPEN inotify event)
and wait until Sudo opendir()s it (because sudo_ttyname_dev() cannot
        find our non-existent pty in "/dev/pts/");

- SIGSTOP Sudo, call openpty() until it creates our non-existent pty,
    and SIGCONT Sudo;

- monitor our directory "/dev/shm/_tmp" (for an IN_CLOSE_NOWRITE inotify
        event) and wait until Sudo closedir()s it;

- SIGSTOP Sudo, replace the symlink "/dev/shm/_tmp/_tty" to our
now-existent pty with a symlink to the file that we want to overwrite
(for example "/etc/passwd"), and SIGCONT Sudo;

- control the output of the command executed by Sudo (the output that
        overwrites "/etc/passwd"):

. either through a command-specific method;

. or through a general method such as "--\nHELLO\nWORLD\n" (by
        default, getopt() prints an error message to stderr if it does not
        recognize an option character).

To reliably win the two SIGSTOP races, we preempt the Sudo process: we
setpriority() it to the lowest priority, sched_setscheduler() it to
SCHED_IDLE, and sched_setaffinity() it to the same CPU as our exploit.




---------
修复
1. centos给的diff文件与上游的diff文件不一样，centos给出的path更加简单
直接地忽略了/dev/shm, /dev/mqueue两个可写的文件夹; 上游给出的解决方案
为：

2. 

