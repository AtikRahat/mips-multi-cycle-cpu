# program.asm - default demo program.
#
# Sums data[0..9] (loaded from data.hex: 1,2,3,...,10) and stores the result
# (55 = 0x37) at mem[10]. Assembled by assembler.py into program.hex/data.hex.

        ADDI $1, $0, 0        # $1 = pointer = 0
        ADDI $2, $0, 0        # $2 = sum = 0
        ADDI $3, $0, 10       # $3 = counter = 10
        ADDI $6, $0, 1        # $6 = constant 1
loop:   BEQ  $3, $0, done     # if counter == 0, exit
        LW   $5, 0($1)        # $5 = mem[pointer]
        ADD  $2, $2, $5       # sum += $5
        ADDI $1, $1, 1        # pointer++
        SUB  $3, $3, $6       # counter--
        BEQ  $0, $0, loop     # unconditional back-edge
done:   SW   $2, 10($0)       # mem[10] = sum
        HALT                  # explicit stop

.data
1
2
3
4
5
6
7
8
9
10
