# program(big_test).asm - alternate test program.
#
# Exercises AND and OR, and both directions of SLT on $1 = 12, $2 = 10,
# then a conditional branch that jumps over ADDI $7, $0, 999, ending in a
# spin loop. Assembled by assembler.py into program(big_test).hex.
# (No .data section - data(big_test).hex is all zeros.)

        ADDI $1, $0, 12
        ADDI $2, $0, 10
        AND  $3, $1, $2
        OR   $4, $1, $2
        SLT  $5, $2, $1       # 10 < 12 -> 1
        SLT  $6, $1, $2       # 12 < 10 -> 0
        BEQ  $1, $2, skip     # not equal -> falls through
        ADDI $7, $0, 999      # skipped
skip:   BEQ  $0, $0, skip     # spin forever
