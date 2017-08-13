# memcached

high-performance (k,v) mem storage, designed to use as cache.

every (k,v) is called an item in mc.

main data struture:

item:  (k,v) in memcached
slabs: slabs sub system
hash:  item index
lru:   lru queue


------
item

ITEM_SLABBED    : item not used but alloced in slabs, aka free in slabs
ITEM_CHUNK      : item chunk data
ITEM_CHUNKED    : item chunk head
ITEM_FETCHED    : item accessed at least once after set, i.e. item active
ITEM_LINKED     : item linked into lru queue and hash

item state trans:

ITEM_SLABBED    -> 

ITEM_CHUNK      -> 

ITEM_CHUNKED    -> 

ITEM_FETCHED    -> 

ITEM_LINKED     -> 


------
slabs

slabs module: slabsclass[64]:
                         slots[]:
                         slab_list[]:
        

rebalance

thread wait for rebalance signal on init, wait for `slab_reassaign` ;

client command `slabs reassign <src> <dst>` or eviction when automove=2 or lru_maintain when automove=1;

start reassign process if slabs > 2;




------
hash

init
rehash

------
lru


