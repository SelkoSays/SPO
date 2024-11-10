CAT	START	0

DEV	BYTE	0

PROG
	CLEAR	A
	STCH	DEV
	JSUB	blk_u_r

	RD	DEV

	COMP	#0
	JEQ	halt

	RMO	A, X

	LDA	#1
	STCH	DEV
	JSUB	blk_u_r

	RMO	X, A

	WD	DEV

	J	PROG

halt	J	halt


. block until DEV ready
blk_u_r	TD	DEV
	JGT	blk_u_r
	RSUB
	END	PROG