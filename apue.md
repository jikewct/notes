* locale  

    #include <locale.h>
    char *setlocale(int category, const char *locale)
    locale == "", set according to ENV
    locale == NULL, query current

    setlocale(LC_ALL, ""); //program made portable

# apue

* pipe(int fd[2])  fd0, fd1分别是pipe的读写端。
* isatty 判断fd是否指向一个terminal，可用于判断是否进行了pipe或者redirect 
* 窗口大小： 

* 文件与目录
判断文件存在
文件大小
文件读取
文件写入

* option

struct option {
    char    *name;
    int     has_arg;
    int     *flag;
    int     val;
}

extern char *optarg;
extern int  optind, opterr, optopt;

int getopt_long(int argc, char **argv, char *lopts, 
            option *lopts, int *longindex);
 

如果选项合法，返回选项
如果选项不合法，返回 '?'


* poll 中的fd如果出现POLLERR，那么poll的返回值为-1？什么情况会出现POLLERR?
