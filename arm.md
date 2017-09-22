# arm

arm is a different architecture from x86.

- Havard arch
- thumb/thumb2 16bit/32bit mixed
- NMI + 1~240 IRQ
- hardware stack!
- register pure and simple
- thread and process mode

## arch

- data-processing operation only operate on register, not directly on mem
- 32 general-purpose 32-bit register, 16 of these are visible
- usr/privileged mode, SWI provides trap facility
- three special role register: SP(R13), LR(R14), PC(R15)
- 7 type of exception, and a privileged mode for each type
    (reset, undefied instruction, SWI, prefetch abort, data abort, IRQ, FIQ)
- status reg holds processor states

## instructions

- ldr           load to register
- blx           branch and link, used when call subroutine
- @             comment
- mov32         move 32bit data
- str           assign value to mem from register
- orr           or
- dsb           memory barrier
- svc           
- itt           


