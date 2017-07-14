-------
libvirt 开发仓库 入库

54作为开发仓库，含有三个remote，三个branch。

三个remote分别是：

centos  srzhao@172.20.51.54:/home/srzhao/work/libvirt/libvirt-centos (fetch)
centos  srzhao@172.20.51.54:/home/srzhao/work/libvirt/libvirt-centos (push)
origin  srzhao@172.18.64.196:/home/srzhao/work/libvirt-upel (fetch)
origin  srzhao@172.18.64.196:/home/srzhao/work/libvirt-upel (push)
upstream        srzhao@172.20.51.54:/home/srzhao/work/libvirt/libvirt-upstream (fetch)
upstream        srzhao@172.20.51.54:/home/srzhao/work/libvirt/libvirt-upstream (push)

其中centos为从git.centos.org克隆下来仓库；
其中upstream为从github克隆下来的仓库；
origin为196上的中转仓库（通过196中转到122服务器）；


三个branch分别是：

c7
upel
v1.3.1-maint


其中c7为centos仓库对应的c7分支；
v1.3.1-maint为upstream仓库对应的v1.3.1-maint分支；
upel为upel维护的代码分支



开发时：
1. 分别从centos和upstream pull最新的代码
2. 针对特定的漏洞（或者功能）选取c7或者v1.3.1-maint分支的某些commit
3. 解决冲突
4. 对代码进行测试，review
5. 提交

--------------------

libvirt 生产仓库 入库：

生产仓库仿照centos对patch和spec进行维护

当开发仓完成开发后；

1. 开发仓format patch生成和上个版本的patch
2. 对应修改spec（path，changelog）
3. 提交pathch，spec修改
4. 编译打包

------------------
尝试找到es打包的libvirt与上游版本的差别

es与upstream
es与v1.3.1-maint最接近，与tag v1.3.1 v1.3.1-rc1 v1.3.1-rc2均不同

es与centos
centos 采用的版本为1.2.17和2.0.0与es采用的版本不同。

centos与upstream


upstream 的tag和release的关系： upstream的tag和release内容不一样（tag的至少没有configure）

tag 只是对源代码的一个标记
release则是根据tag源代码进行一些预处理之后在进行发布



---------------------------

1.3.1 backport的代码


\src\security\security_selinux.c 73c3997f0ff31ce616f3fefa6f7ef5ab091260c1

\src\qemu\qemu_process.c 58832fe4376148b840bb684cb523823ca6444c32

\src\logging\log_manager.c bce46d6a890d72906b01232b030c51fe61821f31

\include\Makefile.am  f464e07f21eee58df92f8d426667f613b305dd17 d8cc67931cdda2a37a1ab2661eb00282acec802c


libvirt-es 跟进上游v1.3.1-maint分支
收录了release 1.3.1(8fd68675e2b5eed5b2aae636544a0a80f9fc70e) 到 (73c3997f0ff31ce616f3fefa6f7ef5ab091260c1)
的更新。



