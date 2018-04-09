
# 从sles迁移到upel的注意点


本文主要讨论应用从当前生产环境的操作系统sles11sp2, sles11sp4，sles12sp1
迁移到upel需要注意的问题。

涉及组件的版本如下：

| package\dist | sles11sp2 | sles11sp4 | sles12sp1 | upel1.0.x |
| gcc          | 4.3.4     | 4.3.4     | 4.3.4     | 4.8.5     |
| glibc        | 2.11.3    | 2.11.3    | 2.19      | 2.17      |
| openssl      | xx        | xx        | xx        | xx        |

## gcc

由于目前sles的gcc版本均为4.3.4，upel为4.8.5，因此本文讨论的是从gcc4.3.4
迁移到4.8.5的注意点。

从宏观上看，高版本gcc执行了更加严格的编译期检测，所以应用在upel上重新编译
可能会出现更多的警告（如果使用了-Werror，则编译不通过），但这些警告能够给
提高应用的稳健性提供更多的信息。

从细节上看，以下给出了迁移过程常见问题以及应对方法：


1. 头文件依赖

高版本gcc清理了非必要的#include，因此可能需要显示#include某些头文件，应用
才能成功编译。

- c++ 使用 uint32_t 必须 #include <stdint.h> 
- c++ 使用 std::printf 必须 #include <stdio.h> 
- c++ 使用 std::printf 必须 #include <stdio.h> 
- c++ 使用 NULL,offsetof,size_t,ptrdiff_t 必须 #include <stddef.h> 
- c++ 使用 truncate,sleep,pipe 必须 #include <unistd.h> 

2. 预编译

```
#if 1
#elif   /* 改为 #else */
#endif
```

3. 编译

a) -Wunused-but-set-variable

```
void fn (void)
{
    int foo;
    foo = bar ();  /* foo is never used.  */
                   /* workaroud, -Wno-error=unused-but-set-variable */
}
```

b)  -fno-strict-aliasing


```
struct A 
{ 
      char data[14];
        int i; 
};

void foo()
{
      char buf[sizeof(struct A)];
        ((struct A*)buf)->i = 4;  /* 不允许此类转换
                                    workaround: -fno-strict-aliasing */
}
```

c)  -Wmaybe-uninitialized.

有些没有初始化的变量将会产生warnning

d) -Wsizeof-pointer-memaccess

```
A obj;
A* p1 = &obj;
memset(p1, 0, sizeof(p1));  /* sizeof ptr error */
                            /* workaround -Wno-sizeof-pointer-memaccess */
```

e) More aggressive loop optimizations

参考 [porting guide 4.8](https://gcc.gnu.org/gcc-4.8/porting_to.html)


4. 链接

高版本gcc不允许链接出现非法参数，因此

```
gcc -Wl -o foo foo.o -mflat_namespace
```
将无法执行，因为-mflat_namespace不是链接参数。



5. 库函数

a) 严格的cstring函数

| <cstring> | strchr, | strpbrk, | strrchr, | strstr, | memchr  |
| <cwchar>  | wcschr  | wcspbrk, | wcsrchr, | wcsstr, | wmemchr |

以上函数如果传入参数为const char*则返回值也是const char*,比如

```
const char* str1;
char* str2 = strchr(str1, 'a');
```
将无法编译。




更多关于gcc迁移注意点的详细信息，参考官方porting文档:

[4.4](https://gcc.gnu.org/gcc-4.4/porting_to.html)
[4.5](https://gcc.gnu.org/gcc-4.5/porting_to.html)
[4.6](https://gcc.gnu.org/gcc-4.6/porting_to.html)
[4.7](https://gcc.gnu.org/gcc-4.7/porting_to.html)
[4.8](https://gcc.gnu.org/gcc-4.8/porting_to.html)


## glibc

从sles11到upel，glibc版本迁移2.11.3-->2.19；从sles12到upel，glibc
版本迁移2.19-->2.17，本文分别讨论从sles11和sles12迁移到upel不兼容
API。

### sles11-->upel

- RPC implementation in libc is obsoleted
- malloc hook implementation is marked deprecated
- gets obseleted
- compatible Linux kernel >= 2.6.16
- clock_* 不需要链接-lrt
- crypt行为变更

The `crypt' function now fails if passed salt bytes that violate the
specification for those values.  On Linux, the `crypt' function will
consult /proc/sys/crypto/fips_enabled to determine if "FIPS mode" is
enabled, and fail on encrypted strings using the MD5 or DES algorithm
when the mode is enabled.


### sles12-->upel


- clock函数精度变低
- 缺少API：pthread_getattr_default_np, pthread_setattr_default_np 
- 缺少_DEFAULT_SOURCE宏


关于glibc的Changelog，参考[The GNU C Library Release Timeline](https://sourceware.org/glibc/wiki/Glibc%20Timeline)


## openssl



--------------------------



gcc 4.3.4 ---> gcc 4.8.5
glibc 2.11.3 --> 2.17

## redhat文档

[ref](https://access.redhat.com/solutions/19458)

gcc版本：
RHEL7 : gcc 4.8.x
RHEL6 : gcc 4.4.x
RHEL5 : gcc 4.1.x
RHEL4 : gcc 3.4.x
RHEL3 : gcc 3.2.x
DTS6 : gcc 6.2.x
DTS4 : gcc 5.2.x, 5.3.x
DTS3 : gcc 4.9.x
DTS2 : gcc 4.8.x
DTS1 : gcc 4.7.x

Compiler backward compatibility packages

Compatibility packages are available to provide build compatibility with code designed to be built under earlier releases:
RHEL7:
compat-gcc-44 (gcc 4.4.7 for compatibility with code designed to be built under RHEL6)
RHEL6:
compat-gcc-34 (gcc 3.4 for compatibility with code designed to be built under RHEL4)
RHEL5:
compat-gcc-34 (gcc 3.4 for compatibility with code designed to be built under RHEL4)
RHEL4:
compat-gcc-32 (gcc 3.2 for compatibility with code designed to be built under RHEL3)
RHEL3:
compat-gcc   (gcc-2.96.x compatible)



Runtime backward compatibility packages

Compatibility packages are available to provide runtime compatibility for binary C++ code that was built under earlier releases:
RHEL7:

compat-libstdc++-33 (g++ 3.3.x compatible)
RHEL6:
compat-libstdc++-33 (g++ 3.3 compatible)
compat-libstdc++-296 (g++ 2.96.x compatible)
RHEL5:
compat-libstdc++-33 (g++ 3.3 compatible)
compat-libstdc++-296 (g++ 2.96.x compatible)
RHEL4:
compat-libstdc++-33 (g++ 3.3 compatible)
compat-libstdc++-296 (g++ 2.96.x compatible)

You will need an active Red Hat Enterprise Linux Developer subscription to gain access to Red Hat Developer Tool set.


------------------




总结:
- 在centos7上有后向兼容的库
- 在centos6上可以利用devtoolset实现前向兼容
- 关于migrate的文档
- 组件的稳定性分类https://access.redhat.com/sites/default/files/attachments/rhel6_app_compatibility_wp.pdf


------------------
## changelog

从changelog来看，上游的gcc直接就是4.8上开始开发的
el7.0 gcc 4.8.2
el7.1 gcc 4.8.3
el7.2 gcc 4.8.5
el7.3 gcc 4.8.5
el7.4 gcc 4.8.5


上游的changelog:

gcc本身的changelog文件的描述有点简单，没有站在兼容性的角度描述。

网站changelog：

4.8
- DWARF4变成了默认的debug信息格式（之前的默认格式为DWARF2） 
- 新选项 -Wsizeof-pointer-memaccess (also enabled by -Wall)，制止使用sizeof(ptr)
- -Wpedantic 替代了-pedantic
- 更完善的c++11支持

4.7
- -fconserve-space deprecated
- 新增-Wunused-local-typedefs
- 新增c11/c++11原子操作内存模型 __atomic
- 支持 -std=c11 -std=gnu11 参数
- G++ now accepts the -std=c++11, -std=gnu++11, and -Wc++11-compat options, which are equivalent to -std=c++0x, -std=gnu++0x, and -Wc++0x-compat, respectively
- __cplusplus 目前值: 199711L for C++98/03, and 201103L for C++11.
- 新增-Wdelete-non-virtual-dtor 
- 新增-Wzero-as-null-pointer-constant 

4.6
- 交叉编译使用方式改变
- 更加严格的命令行参数检查，比如之前的gcc在链接时会忽略--as-needed,--export-dynamic，现在应使用-Wl,--as-needed类似的命令行
- cproj的错误实现被更正
- -combine移除，引入LTO进行替代
- 新增-Wunused-but-set-variable (-Wall开启） -Wunused-but-set-parameter (-Wall -Wextra开启）
- 新增-Wdouble-promotion，警告float隐式升级为double
- 新增关键字a_Static_assert 
- 警告 int转换为pointer -Wno-int-to-pointer-cast关闭warning
- 新增 -Wnoexcept
- -Wshadow警告类型shadow

4.5
- 浮点数运算在 strict C99 conformance mode可能比之前版本慢很多（标准更严），使用-fexcess-precision=fast避免
- noinline修改为noclone
- #include如果没有找到指定的头文件，gcc将直接退出，以避免更多奇怪的错误
- 新增 -Wenum-compare，警告不同的enum比较， enabled by -Wall
- 新增 -Wcast-qual，警告将nononst转换为const, For example, it warns about a cast from char ** to const char **.
- -Wc++-compat新增了更多的警告信息
- -Wjump-misses-init，警告goto或者switch跳过变量初始化 enabled by -Wc++-compat.
- gcc将constant的定义遵循了c90,c99规范，可能会引发warnning或者错误(GCC now implements C90- and C99-conforming rules for constant expressions. This may cause warnings or errors for some code using expressions that can be folded to a constant but are not constant expressions as defined by ISO C.)

4.4
- Support for <varargs.h> had been deprecated
- c++使用assertion扩展在使用-Wdeprecated or -pedantic时将产生警告
- Wparentheses新增警告，比如(!x | y) and (!x & y)，需要显示使用括号((!x) | y)


## porting guide

4.4

- Stricter aliasing requirement

====== c
struct A 
{ 
      char data[14];
        int i; 
};

void foo()
{
      char buf[sizeof(struct A)];
        ((struct A*)buf)->i = 4;
}

将产生警告：
warning: dereferencing type-punned pointer will break strict-aliasing rules

通过-Wno-strict-aliasing临时避免

====== c++
- Header dependency changes

c++ 使用std::printf不包含<cstdio>或者使用uint32_t不包含<stdint.h>将无法编译

- Strict null-terminated sequence utilities

以下函数如果传入参数为const char*，那么返回值也是const char*

<cstring>   strchr, strpbrk, strrchr, strstr, memchr
<cwchar>    wcschr wcspbrk, wcsrchr, wcsstr, wmemchr

因此以下代码无法编译：

const char* str1;
char* str2 = strchr(str1, 'a');

4.6
====== c
- New warnings for unused variables and parameters

void fn (void)
{
    int foo;
    foo = bar ();  /* foo is never used.  */
}

As a workaround, add -Wno-error=unused-but-set-variable or -Wno-error=unused-but-set-parameter.

====== c++
- Header dependency changes
使用NULL或者offsetof 但是没有include <cstddef>无法编译：

error: 'ptrdiff_t' does not name a type
error: 'size_t' has not been declared
error: 'NULL' was not declared in this scope
error: there are no arguments to 'offsetof' that depend on a template
parameter, so a declaration of 'offsetof' must be available

4.7 
====== c
- Use of invalid flags when linking
gcc -Wl -o foo foo.o -mflat_namespace

将产生以下错误：
error: unrecognized command line option ‘-Wl’
error: unrecognized command line option ‘-mflat_namespace’

====== c++


- Header dependency changes

使用了truncate, sleep or pipe但是没有include <unistd.h>的程序无法编译:
error: ‘truncate’ was not declared in this scope
error: ‘sleep’ was not declared in this scope
error: ‘pipe’ was not declared in this scope
error: there are no arguments to 'offsetof' that depend on a template
parameter, so a declaration of 'offsetof' must be available

有些高级特性看不太懂：

[参考](https://gcc.gnu.org/gcc-4.7/porting_to.html)

4.8

====== general

- New warnings
更加严格的-Wmaybe-uninitialized检测，workaround:添加-Wno-maybe-uninitialized.

- More aggressive loop optimizations

For example,

unsigned int foo()
{
    unsigned int data_data[128];

    for (int fd = 0; fd < 128; ++fd)
        data_data[fd] = fd * (0x02000001); // error

    return data_data[0];
}
When fd is 64 or above, fd * 0x02000001 overflows, which is invalid for signed ints in C/C++.

To fix, use the appropriate casts when converting between signed and unsigned types to avoid overflows. Like so:

data_data[fd] = (uint32_t) fd * (0x02000001U); // ok


====== c

- Wno-sizeof-pointer-memaccess.

Wall has changed and now includes the new warning flag -Wsizeof-pointer-memaccess

- Pre-processor pre-includes



## 关于glibc

el7的所有版本的glibc都是2.17


2.18 
- clock 使用 clock_gettime系统调用，比之前的time系统调用更精确
- 新增 pthread_getattr_default_np, pthread_setattr_default_np 
- 修复了CVE-2013-2207,CVE-2013-0242,CVE-2013-1914

2.19
- 修复CVE-2012-4412,CVE-2012-4424,CVE-2013-4788,CVE-2013-4237, CVE-2013-4332,CVE-2013-4458
- 新增_DEFAULT_SOURCE宏，用于添加默认include文件

