SCREEN	START	0

PROG
	LDA	#48	. ASCII(48) = '0'
	JSUB	scrfill

	JSUB	scrclear

halt	J	halt

scrclear
	CLEAR	A
. A = CHAR, fill screen with CHAR
scrfill
	+STX	tmp
	LDX	#0
loop
	+STCH	screen, X
	TIX	#scrlen
	JLT	loop

	+LDX	tmp
	RSUB

screen	EQU	0xB800
scrcols	EQU	80
scrrows	EQU	25
scrlen	EQU	scrcols * scrrows

tmp	WORD	0
	END	PROG