STACK	START	0

	JSUB	stackinit

halt	J	halt

stackinit
	+STA	stkA
	+LDA	#stktop
	+STA	stkptr
	+LDA	stkA
	RSUB

stackpush
	+STA	stkA

	+LDA	#stkof_s
	+STA	stk_str

	+LDA	stkptr
	+COMP	#stk
	JEQ	stkerr
	JLT	stkerr

	+SUB	stkwrd
	+STA	stkptr
	+LDA	stkA
	RSUB

stackpop
	+STA	stkA

	+LDA	#stkuf_s
	+STA	stk_str

	+LDA	stkptr
	+COMP	#stktop
	JGT	stkerr

	+ADD	stkwrd
	+STA	stkptr
	+LDA	stkA
	RSUB

stkerr	. Stack Error
	LDX	stk_str
	LDS	#1
	CLEAR	A
serr_l	LDCH	0, X
	COMP	#0
	JEQ	SErrEnd
	WD	#1
	ADDR	S, X
	J	serr_l
SErrEnd	J	SErrEnd

. STACK
stkA	WORD	0
stk	RESW	1
stktop	RESW	1
stkptr	WORD	0
stkwrd	WORD	3	. STACK WORD SIZE

stk_str	WORD	0
dummy	BYTE	0
stkof_s	BYTE	C'Stack Overflow'
	BYTE	10
	BYTE	0
stkuf_s	BYTE	C'Stack Underflow'
	BYTE	10
	BYTE	0

undef	EQU	0x666666 . undefined = 0b1010...	
	END	STACK