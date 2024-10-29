. SHOULD BE RUN AT 60000
BB	START	0
PROG
	JSUB	stkinit
	JSUB	ballInit

lLoop
	JSUB	mvBalls
	J	lLoop
	
. Move balls
mvBalls
	STL	@stkptr
	JSUB	PUSH
	STA	@stkptr
	JSUB	PUSH
	STX	@stkptr
	JSUB	PUSH
	STT	@stkptr
	JSUB	PUSH

	LDX	#balls
	LDA	#bLen
	MUL	#bSize
	ADD	#balls
	RMO	A, T

mvbLoop
	COMPR	X, T
	JEQ	mvbEndLoop
	JGT	mvbEndLoop

. ERASE BALL'S LAST POS ON SCREEN
.--------------------------------------
	LDA	#0
	STA	arg1
	
	. X POS
	LDA	0, X
	STA	arg2
	
	. Y POS
	LDA	3, X
	STA	arg3

	JSUB	dspChar
.--------------------------------------

. CHANGE X
.--------------------------------------
mvbXP	LDA	0, X	. LOAD X POS
	ADD	6, X	. ADD  X VEL

	. SHOULD BE 0 <= Y < HEIGHT
	COMP	#0
	JLT	mvbCXVS
	COMP	#width
	JLT	mvbSkipX

mvbCXVS . change X velocity sign
	CLEAR 	A
	SUB	#1
	MUL	6, X
	STA	6, X
	J	mvbXP
mvbSkipX
	STA	0, X	. STORE NEW X POS
.--------------------------------------

. CHANGE Y
.--------------------------------------
mvbYP	LDA	3, X	. LOAD Y POS
	ADD	9, X	. ADD  Y VEL

	. SHOULD BE 0 <= Y < HEIGHT
	COMP	#0
	JLT	mvbCYVS
	COMP	#height
	JLT	mvbSkipY

mvbCYVS . change Y velocity sign
	CLEAR 	A
	SUB	#1
	MUL	9, X
	STA	9, X
	J	mvbYP

mvbSkipY
	STA	3, X	. STORE NEW Y POS
.--------------------------------------

. DISPLAY BALL ON SCREEN
.--------------------------------------
	LDA	#111	. 111 = 'o'
	STA	arg1
	
	. X POS
	LDA	0, X
	STA	arg2
	
	. Y POS
	LDA	3, X
	STA	arg3

	JSUB	dspChar
.--------------------------------------

	LDA	#bSize
	ADDR	A, X
	J	mvbLoop

mvbEndLoop
	JSUB	POP
	LDT	@stkptr
	JSUB	POP
	LDX	@stkptr
	JSUB	POP
	LDA	@stkptr
	JSUB	POP
	LDL	@stkptr
	RSUB

. Init Balls
ballInit
	STL	@stkptr
	JSUB	PUSH
	STA	@stkptr
	JSUB	PUSH
	STX	@stkptr
	JSUB	PUSH
	STT	@stkptr
	JSUB	PUSH

	LDX	#balls
	LDA	#bLen
	MUL	#bSize
	ADD	#balls
	RMO	A, T

bLoop	COMPR	X, T
	JEQ	bEndLoop
	JGT	bEndLoop

	. RANDOM X POS
	LDA	#1
	STA	arg1
	LDA	#width - 1
	STA	arg2
	JSUB	rand
	LDA	arg1
	STA	0, X
	
	LDA	#3
	ADDR	A, X

	. RANDOM Y POS
	LDA	#1
	STA	arg1
	LDA	#height - 1
	STA	arg2
	JSUB	rand
	LDA	arg1
	STA	0, X

	LDA	#3
	ADDR	A, X

	. RANDOM X VEL
	CLEAR	A
	STA	arg1
	LDA	#2
	STA	arg2
	JSUB	rand
	LDA	arg1
	MUL	#3
	. choose -1 or 1
	STX	svx
	LDX	#CHOICE
	ADDR	A, X
	LDA	0, X
	LDX	svx
	STA	0, X

	LDA	#3
	ADDR	A, X

	. RANDOM Y VEL
	CLEAR	A
	STA	arg1
	LDA	#2
	STA	arg2
	JSUB	rand
	LDA	arg1
	MUL	#3
	. choose -1 or 1
	STX	svx
	LDX	#CHOICE
	ADDR	A, X
	LDA	0, X
	LDX	svx
	STA	0, X

	LDA	#3
	ADDR	A, X

	J	bLoop
bEndLoop

	JSUB	POP
	LDT	@stkptr
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
	JSUB	blk_u_r
	WD	#1
	ADDR	S, X
	J	serr_l
SErrEnd	J	SErrEnd

. stdout
. block until ready
blk_u_r	TD	#1
	JGT	blk_u_r
	RSUB

. Display char on screen
. arg1 = char, arg2 = xpos, arg3 = ypos
dspChar
	STL	@stkptr
	JSUB	PUSH
	STA	@stkptr
	JSUB	PUSH
	STX	@stkptr
	JSUB	PUSH

	. IDX = (WIDTH * Y) + X
	LDA	#width
	MUL	arg3
	ADD	arg2
	+ADD	#scraddr

	RMO	A, X
	LDA	arg1
	STCH	0, X

	JSUB	POP
	LDX	@stkptr
	JSUB	POP
	LDA	@stkptr
	JSUB	POP
	LDL	@stkptr

	RSUB

.DATA

.screen
width	EQU	80
height	EQU	25
pxlen	EQU	width * height
scraddr	EQU	0xB800

. rand data
rnd_cur	WORD	143	. SEED
rnd_mul	WORD	53
rnd_add	WORD	13

.Ball
.  pos x,y [0, WIDTH], [0, HEIGHT]
.  vel x,y {-1, 1}
.SIZEOF(Ball) = 3 + 3 + 3 + 3 = 12B
. b_px	WORD	0	. offset of field px
. b_py	WORD	3	. offset of field py
. b_vx	WORD	6	. offset of field vx
. b_vy	WORD	9	. offset of field vy

bLen	EQU	9
bSize	EQU	12
balls	RESW	bLen * bSize . array of balls

svx	RESW	1
CHOICE	WORD	-1
	WORD	1

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
arg3	WORD	0
	END	PROG