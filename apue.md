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
 
