.extern interruptHandler

// Macros
.macro isrNoErrStub interruptNum
    isr_stub_\interruptNum:
		movq $0, %rsi
        isrCommonStub \interruptNum
.endm
.macro isrErrStub interruptNum
    isr_stub_\interruptNum:
		pop %rsi
		isrCommonStub \interruptNum
.endm
.macro isrCommonStub interruptNum
	movq $\interruptNum, %rdi
    call interruptHandler
    iretq
.endm

// Load the GDT
.global loadGDT
loadGDT:
	lgdt (%rdi)

	// Should point to the kernel code segment
	// The kernel CS is the second entry in the GDT
	pushq $0x08

	// Reload code segments and perform a far return
	leaq .reloadCS(%rip), %rax
	pushq %rax
	lretq
.reloadCS:
	movw $0x10, %ax
	movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
	ret

// Load the IDT
.global loadIDT
loadIDT:
	lidt (%rdi)
	ret

// Create interrupt service routines
.rept 48
	.if (\+ == 8) || (\+ == 10) || (\+ == 11) || (\+ == 12) || (\+ == 13) || (\+ == 14) || (\+ == 17) || (\+ == 30)
		isrErrStub \+
	.else
		isrNoErrStub \+
	.endif
.endr

// Place all ISRs in an array that we can easily use
.global isrStubTable
isrStubTable:
	.rept 48
		.quad isr_stub_\+
	.endr
