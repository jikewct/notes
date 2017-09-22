# pkioRT

RTOS for arm cotex-m

## build

Makefile can divide in three sections:

1. cmsis download
2. compile objects
3. link objects into bin & objcopy to elf

## boot

arm boot process is diffrent from x86 boot process, i'd say it's more elegant
than x86 (historical reasons).

[starting-process-for-arm](https://stackoverflow.com/questions/6139952/what-is-the-booting-process-for-arm)

```
__Vectors       DCD     __initial_sp              ; Top of Stack
                DCD     Reset_Handler             ; Reset Handler
                DCD     NMI_Handler               ; NMI Handler
                DCD     HardFault_Handler         ; Hard Fault Handler
                DCD     MemManage_Handler         ; MPU Fault Handler
                DCD     BusFault_Handler          ; Bus Fault Handler
                DCD     UsageFault_Handler        ; Usage Fault Handler
                [...more vectors...]
```

vector specified in /arch/v7m-head.S:

```
	ldr	r0, =SystemInit			/* CMSIS system init */
	blx	r0
```

so, piko would start from SystemInit when power on.

## kernel


## driver

## libc

a tiny real-time kernel.

## build


