# Makefile

- 特殊符号
 $@ 输出文件名; @^ 所有依赖; @< 第一个依赖;

- include   
与c语言include类似, -include不存在等错误

- suffix rule 
    已经由pattern rule代替,但仍然兼容.
    分为两种：single suffix rule(e.g. .c) & double suffix rule(e.g. .c.o)
    .c .o在默认的suffixes中，.SUFFIXES : .c .o .xo .so 指明.xo .so等suffix
    举例如下:
    .c.o:
        $(CC) -c $(CFLAGS) -o $@ $<

- gmake & make
gmake特指GNU implemented make, make 指系统默认make。
大多数linux中make默认是gmake， bsd中的是bsd make，其他的商业unix中使用的可能是其他make。

- multiple rule for one target
多个prerequisite合并，多个receipt报错, 典型示例如下：
objects = foo.o bar.o
foo.o : defs.h
bar.o : defs.h test.h
$(objects) : config.h

- antirez/redis Makefile 风格
gcc -MM \*.c 动生成依赖关系;
suffix rule (.c.o) 声明.o依赖的.c;
bin: a.o b.o

优点：
    需要手动写的是bin生成的规则
    其他的规则自动生成，简单明确

