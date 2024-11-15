. SCREEN 80 cols x 25 rows
DISPLAY	WORD	0xB800
CHR	WORD	48
SCRSZ	RESW	1

ARGS	RESW	2
STKMOD	RESW	4
STRX	RESW	1

PROG	LDA	#80
	MUL	#25
	STA	SCRSZ

	LDA	DISPLAY
	LDT	SCRSZ
	ADDR	A,T

	LDA	CHR
	LDS	#1
	LDX	DISPLAY

LOOP	STCH	0, X
	ADD	#1
	SUB	CHR

	STX	STRX
	LDX	#ARGS
	STA	0, X
	LDA	#10	. '0' = 48 ... '9' = 57
	STA	3, X
	LDX	STRX

	JSUB	MOD
	LDA	ARGS
	ADD	CHR

	ADDR	S,X
	COMPR	X, T
	JLT	LOOP

HALT	J	HALT

. STEVEC = (ARGS), IMENOVALEC = (ARGS) + 3
. RETVAL = (ARGS)
MOD
	STX	STKMOD
	LDX	#STKMOD
	STA	3, X
	STS	6, X
	STL	9, X
	LDX	#ARGS
	LDA	0, X

	DIV	3, X
	MUL	3, X
	RMO	A, S
	LDA	0, X
	SUBR	S, A
	STA	0, X

	LDX	#STKMOD
	LDA	3, X
	LDS	6, X
	LDL	9, X
	LDX	STKMOD
	RSUB
	
	END	PROG