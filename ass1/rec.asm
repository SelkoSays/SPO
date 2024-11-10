REC	START	0

dev	BYTE	0xFA
arg1	WORD	0
arg2	WORD	0

me	WORD	-1

PROG
	JSUB	stackinit

loop
	JSUB	rdnum
	LDA	arg1
	COMP	#0
	JEQ	halt

	JSUB	fakulteta
	LDA	arg1
	COMP	#1
	JLT	num_overflow
no_of	JSUB	wrtnum
	LDA	#10
	WD	#1
	J	loop

num_overflow
	LDA	me
	STA	arg1
	J	no_of

halt	J	halt

. arg1 = num
fakulteta
	STL	@stkptr
	JSUB	stackpush
	STA	@stkptr
	JSUB	stackpush

	LDA	arg1

	COMP	#2
	JLT	skip

	SUB	#1
	STA	arg1
	JSUB	fakulteta
	ADD	#1
	MUL	arg1
	J	sskip

skip
	LDA	#1
sskip	STA	arg1
	JSUB	stackpop
	LDA	@stkptr
	JSUB	stackpop
	LDL	@stkptr
	RSUB

.read num from dev
. assume delim = '\n'
. assume no additional spaces
. assume only number characters
rdnum
	STL	@stkptr
	JSUB	stackpush
	STA	@stkptr
	JSUB	stackpush
	STS	@stkptr
	JSUB	stackpush

	CLEAR	A
	STA	arg1
	RD	dev
	COMP	#48	. ASCII(48) = '0'
	JEQ	erdnum

loop1
	COMP	#10	. ASCII(10) = \n
	JEQ	erdnum

	SUB	#48
	RMO	A, S
	LDA	arg1
	MUL	#10
	ADDR	S, A
	STA	arg1

	RD	dev
	J	loop1


erdnum
	JSUB	stackpop
	LDS	@stkptr
	JSUB	stackpop
	LDA	@stkptr
	JSUB	stackpop
	LDL	@stkptr
	RSUB

. arg1 = num, print num to stdout
wrtnum
	STL	@stkptr
	JSUB	stackpush
	STA	@stkptr
	JSUB	stackpush

	LDA	arg1
	COMP	me
	JGT	skipM
	LDA	#0x2D	. ASCII(0x2D) = '-'
	WD	#1
	CLEAR	A
	SUB	arg1
	STA	arg1

skipM
	LDA	arg1

	STA	@stkptr
	JSUB	stackpush

	DIV	#10
	COMP	#0
	JEQ	enum

	STA	arg1
	JSUB	wrtnum

enum
	JSUB	stackpop
	LDA	@stkptr
	STA	arg1
	LDA	#10
	STA	arg2
	JSUB	mod
	LDA	arg1
	ADD	#48	. ASCII(48) = '0'
	WD	#1

	JSUB	stackpop
	LDA	@stkptr
	JSUB	stackpop
	LDL	@stkptr
	RSUB

. Modulo
. stevec = arg1, imenovalec = arg2
mod
	STL	@stkptr
	JSUB	stackpush
	STA	@stkptr
	JSUB	stackpush

	LDA	arg1
	DIV	arg2
	MUL	arg2

	STA	@stkptr
	JSUB	stackpush

	LDA	arg1
	JSUB	stackpop
	SUB	@stkptr
	STA	arg1

	JSUB	stackpop
	LDA	@stkptr
	JSUB	stackpop
	LDL	@stkptr

	RSUB

. A = char
putc
	WD	dev
	RSUB


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
stk	RESW	511
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
	END	PROG