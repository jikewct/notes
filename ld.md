# ld 

every link is controlled by a linker script, which is written in the linker command language.

main purpose is to describe how sections in the input files should be mapped into the output file, and to control memory layout of the output file.

## information

- ld always use a linker script, -verbose would print default linker script

## concepts

- the input & output file are in a special file format called object file format (e.g. elf)
- linker combines input files into a single output file.
- each object file contains a list of sections.
- a section has a name, size and usually an associated data block called section contents. 
- a section is either loadable or allocatable or containing debugging info.
- a section is either loadable or allocatable or containing debugging info.
- every obejct file has a list of symbols, known as sym table. can be print by `nm` or `objdump -t`

## linker script

- linker scripte contains a series of commands, each command is either a keyword or an assignment to symbol.
- commands is separated by `;`, whitespace is ignored, comment as `/* ... */`

## commands

- SECTIONS          sections specification
- ENTRY             program entry point
- INCLUDE           similar to c `#include`
- INPUT             specify input object files
- GROUP             like `INPUT` but files should be archive
- OUTPUT            default to `a.out`
- SEARCH\_DIR       specify output file
- STARTUP           like `INPUT` but file is the first to link

- OUTPUT\_FORMAT    specify bfd file format.
- TARGET            specify input bfd file format.

- ASSERT            asserts
- EXTERN            force symbol to be undefined
- FORCE\_COMMON\_ALLOCATION
- INHIBIT\_COMMON\_ALLOCATION
- OUTPUT\_ARCH      

## assign

- You may assign to a symbol using any of the C assignment operators.

```
floating_point = 0;
SECTIONS
{
    .text :
    {
        *(.text)
            _etext = .;
    }
    _bdata = (. + 3) & ~ 3;
    .data : { *(.data) }
}
```

## MEMROY

memory layout can be overrided by MEMORY command, syntax is:

```
MEMORY
{
    name [(attr)] : ORIGIN = origin, LENGTH = len
        …
}
```

- The name is a region which has no meaning outside of the linker script. Region names will not conflict with symbol names.

## SECTION

```
SECTIONS
{
    sections-command
    sections-command
    ...
}
```

sections command can be one of:

- an ENTRY command
- a symbol assignment
- an output section
- an overlay 


output section looks like :

```
section [address] [(type)] : [AT(lma)]
{
    output-section-command
    output-section-command
        …
} [>region] [AT>lma_region] [:phdr :phdr …] [=fillexp]
```

output-section-command can be:

- a symbol assignment
- an input section description
- data value to include directly
- a special section keyword



## example

```
SECTIONS
{
    . = 0x10000;
    .text : { *(.text) }
    . = 0x8000000;
    .data : { *(.data) }
    .bss : { *(.bss) }
}
```


## ref

[using ld](https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/4/html/Using_ld_the_GNU_Linker/)
