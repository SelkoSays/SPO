BB	START	0
PROG
	LDA	width
	MUL	height
	STA	pxlen

	JSUB	stkinit

	LDA	#0
	STA	arg1
	LDA	#5
	STA	arg2
	JSUB	rand
	LDA	arg1

	LDS	#0
	STS	arg1
	LDS	#5
	STS	arg2
	JSUB	rand
	LDS	arg1


	LDB	#0
	STB	arg1
	LDB	#5
	STB	arg2
	JSUB	rand
	LDB	arg1
	

halt	J	halt

. Init Balls
ballInit
	STL	@stkptr
	JSUB	PUSH
	STA	@stkptr
	JSUB	PUSH
	STX	@stkptr
	JSUB	PUSH
	STB	@stkptr
	JSUB	PUSH
	STT	@stkptr
	JSUB	PUSH

	LDX	#0
	LDA	#bLen
	MUL	#bSize
	RMO	A, T

	LDB	#balls
	BASE	balls

	

	NOBASE

	JSUB	POP
	LDT	@stkptr
	JSUB	POP
	LDB	@stkptr
	JSUB	POP
	LDX	@stkptr
	JSUB	POP
	LDA	@stkptr
	JSUB	POP
	LDL	@stkptr

	RSUB

. Modulo
. stevec = arg1, imenovalec = arg2
mod
	STL	@stkptr
	JSUB	PUSH
	STA	@stkptr
	JSUB	PUSH

	LDA	arg1
	DIV	arg2
	MUL	arg2

	STA	@stkptr
	JSUB	PUSH

	LDA	arg1
	JSUB	POP
	SUB	@stkptr
	STA	arg1

	JSUB	POP
	LDA	@stkptr
	JSUB	POP
	LDL	@stkptr

	RSUB


. Random function [min, max)
. min = arg1, max = arg2
rand
	STL	@stkptr
	JSUB	PUSH
	STA	@stkptr
	JSUB 	PUSH

	.store args
	LDA	arg1
	STA	@stkptr
	JSUB	PUSH

	. range
	LDA	arg2
	SUB	arg1
	STA	arg2

	LDA	rnd_cur
	MUL	rnd_mul
	ADD	rnd_add
	COMP	#0
	JGT	rndskip
	STA	rnd_cur
	CLEAR	A
	SUB	rnd_cur
rndskip STA	arg1
	STA	rnd_cur

	JSUB	mod

	LDA	arg1	. RETURN VALUE
	JSUB 	POP	. pop min
	ADD	@stkptr
	STA	arg1

	JSUB	POP
	LDA	@stkptr
	JSUB	POP
	LDL	@stkptr

	RSUB


. Stack initialization
stkinit
	LDA	#stktop
	STA	stkptr
	LDA	#dummy
	STA	stk_str	
	RSUB

PUSH
	STA	stksv

	LDA	#stkof_s
	STA	stk_str

	LDA	stkptr
	COMP	#stkbot
	JEQ	stkerr
	JLT	stkerr
	SUB	#3
	STA	stkptr
	LDA	stksv
	RSUB

POP
	STA	stksv

	LDA	#stkuf_s
	STA	stk_str

	LDA	stkptr
	COMP	#stktop
	JGT	stkerr
	ADD	#3
	STA	stkptr
	LDA	stksv
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

.DATA

.screen
width	WORD	80
height	WORD	25
pxlen	WORD	0

. rand data
rnd_cur	WORD	142	. SEED
rnd_mul	WORD	53
rnd_add	WORD	13

.Ball
.  pos x,y [0, WIDTH], [0, HEIGHT]
.  vel x,y {-1, 0, 1}
.SIZEOF(Ball) = 3 + 3 + 3 + 3 = 12B
b_px	EQU	0	. offset of field px
b_py	EQU	3	. offset of field py
b_vx	EQU	6	. offset of field vx
b_vy	EQU	9	. offset of field vy

bLen	EQU	3
bSize	EQU	12
balls	RESW	bLen * bSize . array of balls

.stack
stksv	RESW	1
stkbot	RESW	20
stktop	RESW	1
stkptr	WORD	0

stk_str	WORD	0
dummy	BYTE	0
stkof_s	BYTE	C'Stack Overflow'
	BYTE	10
	BYTE	0
stkuf_s	BYTE	C'Stack Underflow'
	BYTE	10
	BYTE	0

. Args
arg1	WORD	0
arg2	WORD	0

. Retturn Values
ret1	WORD	0

	END	PROG