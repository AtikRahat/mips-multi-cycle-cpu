# program(sum).asm - alternate test program.
#
# Sums data[0..] until the running sum equals mem[6] (= 6), using a JAL
# back-edge, then stores the result at mem[7] and spins. Assembled by
# assembler.py into program(sum).hex / data(sum).hex.

        ADDI $1, $0, 0        # $1 = index = 0
        ADDI $2, $0, 0        # $2 = sum = 0
        LW   $7, 6($0)        # $7 = mem[6] = 6 (sum threshold)
loop:   BEQ  $1, $7, done     # stop once index == mem[6]
        ADD  $3, $1, $0       # $3 = index
        LW   $4, 0($3)        # $4 = mem[index]
        ADD  $2, $2, $4       # sum += $4
        ADDI $1, $1, 1        # index++
        JAL  loop             # back-edge (absolute target)
done:   SW   $2, 7($0)        # mem[7] = sum
spin:   BEQ  $0, $0, spin     # spin forever

.data
1
2
3
4
5
6
6
