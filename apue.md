* locale  

    #include <locale.h>
    char *setlocale(int category, const char *locale)
    locale == "", set according to ENV
    locale == NULL, query current

    setlocale(LC_ALL, ""); //program made portable
