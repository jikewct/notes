* 关于typedef和struct
参考回答：http://stackoverflow.com/questions/252780/why-should-we-typedef-a-struct-so-often-in-c

* remove trailing '\n' (fgets)
buf[strcspn(buf, '\n')] = 0;

* strdup & strdupa 比 malloc;strcpy 更简洁

* extern IS OPTIONAL on function

* uint32_t defined in stdint.h

* size_t defined in stddef.h

* strspn(const char *s, const char *accept);
    找到s中全由accept中字符组成的连续长度

* strtok
    split string 

* strpbrk - search a string for any of a set of bytes

* goto label, label only have function scope

* restrict c99 keyword, intend for compiler, its' programmer promise of elimiating pointer aliasing
