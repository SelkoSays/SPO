ECHO	START	0

SVL1	RESW	1
SVL2	RESW	1
SVA1	RESW	1
SVA2	RESW	1
SVX1	RESW	1
SVS1	RESW	1

strp	WORD	0

x	WORD	0
y	WORD	0
rmod	WORD	0
mdsva	RESW	1

strnum	RESB	8	. 2**23 = 8_388_608
	BYTE	0
snumE	EQU	*
snumLI	EQU	snumE - strnum - 2	. last index
minus	WORD	0	. true / false

me	WORD	-1

c1	BYTE	C'0'
str1	BYTE	C'Hello World!'
	BYTE	0

num1	WORD	42069
num2	WORD	-42069

PROG
	LDCH	c1
	JSUB	char

	JSUB	nl

	LDA	#str1
	JSUB	string

	JSUB	nl

	LDA	num1
	JSUB	num

	JSUB	nl

	LDA	num2
	JSUB	num

	JSUB	nl

halt	J	halt

. A = char, print char
char
	WD	#1
	RSUB

. print new line
nl
	STL	SVL1
	STA	SVA1
	LDA	#10	. ASCII(10) = \n
	JSUB	char
	LDA	SVA1
	LDL	SVL1
	RSUB

. A = str addr, print str
string
	STL	SVL1

	+STA	strp

loop	+LDCH	@strp

	COMP	#0
	JEQ	eloop

	JSUB	char
	+LDA	strp
	ADD	#1
	+STA	strp

	J	loop

eloop
	LDL	SVL1
	RSUB

. A = NUMBER, print number
num
	STL	SVL2
	STA	SVA1
	STA	SVA2
	STX	SVX1
	STS	SVS1

	LDA	#snumLI
	ADD	#strnum
	RMO	A, X
	LDA	SVA1
	LDS	#1

	COMP	#0
	JLT	setMin
notMin
	STA	x
	LDA	#10
	STA	y
	JSUB	mod

	LDA	rmod
	ADD	#48	. ASCII(48) = '0'
	STCH	0, X

	LDA	SVA1
	DIV	#10
	STA	SVA1

	SUBR	S, X

	COMP	#0
	JGT	notMin

	LDA	minus
	COMP	#0
	JEQ	NM
	LDA	#0x2D	. ASCII(0x2D) = '-'
	STCH	0, X
	SUBR	S, X
NM
	ADDR	S, X
	RMO	X, A
	JSUB	string

	LDA	SVA2
	LDS	SVS1
	LDX	SVX1
	LDL	SVL2
	RSUB

setMin
	STA	SVA1
	LDA	#1
	STA	minus
	LDA	#0
	SUB	SVA1
	STA	SVA1
	J	notMin

. x % y = r_mod
mod
	STA	mdsva

	LDA	x
	DIV	y
	MUL	y
	STA	rmod
	LDA	x
	SUB	rmod
	STA	rmod

	LDA	mdsva
	RSUB

	END	PROG