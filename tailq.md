# TAILQ

bsd发行的列表（队列）头文件, 实现全部用宏。

```c
#define TAILQ_HEAD(name, type)						\
struct name {								\
	struct type *tqh_first;	/* first element */			\
	struct type **tqh_last;	/* addr of last next element */		\
}
```

- 为什么tqh_first是一级指针，tqh_last是一个二级指针？
- type是不是必须是TQILQ_ENTRY?

```c
#define TAILQ_ENTRY(type)						\
struct {								\
	struct type *tqe_next;	/* next element */			\
	struct type **tqe_prev;	/* address of previous next element */	\
}
```

- 为什么tqe_next是一级指针，而tqe_prev是二级指针
