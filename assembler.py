#!/usr/bin/env python3
"""
Tiny MIPS-subset assembler for the custom single-cycle CPU project.

Supports:
  R-type : ADD, SUB, AND, OR, SLT     -> "ADD $rd, $rs, $rt"
  Branch : BEQ, BNE                    -> "BEQ $rs, $rt, label"
  Memory : LW, SW                      -> "LW $rt, offset($rs)"
  Imm    : ADDI                        -> "ADDI $rt, $rs, immediate"
  Jump   : JAL                         -> "JAL label"
           JR                          -> "JR $rs"
  Labels : "label:" on its own line, or "label: INSTRUCTION ..."
  Comments: anything after '#' is ignored

  .data section: everything after a line containing only ".data" is
  treated as initial data-memory contents instead of instructions -
  one value per line (decimal or 0x-prefixed hex), assigned to
  addresses 0, 1, 2, ... in order. Everything before ".data" (or the
  whole file, if there's no ".data" line) is instructions.

Produces TWO files:
  program.hex - instruction memory contents (for imem.v's $readmemh)
  data.hex    - initial data memory contents (512 words, for dmem.v's
                $readmemh)
"""

import utils.session
import re
import sys

FUNCT = {'ADD': 0b100000, 'SUB': 0b100010, 'AND': 0b100100,
         'OR':  0b100101, 'SLT': 0b101010}
RTYPE_OPS = set(FUNCT.keys())
BRANCH_OPCODE = {'BEQ': 0b000100, 'BNE': 0b000101}
MEM_OPCODE = {'LW': 0b100011, 'SW': 0b101011}
ADDI_OPCODE = {'ADDI': 0b001000}
JAL_OPCODE = 0b000011
JR_FUNCT = 0b001000
HALT_OPCODE = 0b111111  # NEW: explicit stop, no operands (was unused opcode)

# NEW: MULT/DIV/MFHI/MFLO - real MIPS encodings (opcode=0, R-type)
MULT_FUNCT = 0b011000
DIV_FUNCT  = 0b011010
MFHI_FUNCT = 0b010000
MFLO_FUNCT = 0b010010
MULTDIV_OPS = {'MULT', 'DIV'}   # format: "MULT $rs, $rt" (no rd - result goes to HI/LO)
MFHILO_OPS = {'MFHI', 'MFLO'}   # format: "MFHI $rd" (no rs/rt - reads HI/LO)


def reg_num(token):
    token = token.strip().strip(',')
    if not token.startswith('$'):
        raise ValueError(f"Expected a register like $5, got '{token}'")
    return int(token[1:])


def strip_comment(line):
    return line.split('#', 1)[0]


def split_sections(text):
    """Split the source into (instruction_text, data_text) at a lone
    '.data' line. If there's no such line, data_text is empty."""
    lines = text.splitlines()
    for i, raw in enumerate(lines):
        if strip_comment(raw).strip().lower() == '.data':
            return '\n'.join(lines[:i]), '\n'.join(lines[i + 1:])
    return text, ''


def parse_lines(text):
    """First pass: split into (label_or_None, mnemonic, operand_string) per real instruction line."""
    instructions = []
    for raw in text.splitlines():
        line = strip_comment(raw).strip()
        if not line:
            continue

        label = None
        m = re.match(r'^(\w+):\s*(.*)$', line)
        if m:
            label = m.group(1)
            line = m.group(2).strip()
            if not line:
                # label-only line: attach to the NEXT real instruction
                instructions.append(['__LABELONLY__', label, None, None])
                continue

        parts = line.split(None, 1)
        mnemonic = parts[0].upper()
        operands = parts[1] if len(parts) > 1 else ''
        instructions.append([mnemonic, label, operands, raw])

    # merge label-only lines into the following instruction
    merged = []
    pending_label = None
    for entry in instructions:
        if entry[0] == '__LABELONLY__':
            pending_label = entry[1]
            continue
        mnemonic, label, operands, raw = entry
        if pending_label is not None:
            label = pending_label
            pending_label = None
        merged.append((mnemonic, label, operands, raw))
    return merged


def first_pass(instrs):
    """Compute address of every label."""
    labels = {}
    for addr, (mnemonic, label, operands, raw) in enumerate(instrs):
        if label:
            if label in labels:
                raise ValueError(f"Duplicate label '{label}'")
            labels[label] = addr
    return labels


def encode_rtype(mnemonic, operands):
    ops = [o.strip() for o in operands.split(',')]
    rd, rs, rt = reg_num(ops[0]), reg_num(ops[1]), reg_num(ops[2])
    funct = FUNCT[mnemonic]
    return (0 << 26) | (rs << 21) | (rt << 16) | (rd << 11) | (0 << 6) | funct


def encode_branch(mnemonic, operands, addr, labels):
    ops = [o.strip() for o in operands.split(',')]
    rs, rt, target_label = reg_num(ops[0]), reg_num(ops[1]), ops[2]
    if target_label not in labels:
        raise ValueError(f"Unknown label '{target_label}'")
    offset = labels[target_label] - (addr + 1)
    if not (-32768 <= offset <= 32767):
        raise ValueError(f"Branch offset {offset} out of 16-bit range")
    opcode = BRANCH_OPCODE[mnemonic]
    return (opcode << 26) | (rs << 21) | (rt << 16) | (offset & 0xFFFF)


def encode_mem(mnemonic, operands):
    # format: $rt, offset($rs)
    m = re.match(r'\$(\d+)\s*,\s*(-?\d+)\s*\(\s*\$(\d+)\s*\)', operands.strip())
    if not m:
        raise ValueError(f"Bad memory operand syntax: '{operands}' (expected $rt, offset($rs))")
    rt, offset, rs = int(m.group(1)), int(m.group(2)), int(m.group(3))
    opcode = MEM_OPCODE[mnemonic]
    return (opcode << 26) | (rs << 21) | (rt << 16) | (offset & 0xFFFF)


def encode_addi(operands):
    # format: $rt, $rs, immediate  (immediate: decimal or 0x-prefixed hex)
    ops = [o.strip() for o in operands.split(',')]
    if len(ops) != 3:
        raise ValueError(f"ADDI expects '$rt, $rs, immediate', got '{operands}'")
    rt, rs = reg_num(ops[0]), reg_num(ops[1])
    imm = int(ops[2].strip(), 0)
    if not (-32768 <= imm <= 32767):
        raise ValueError(f"ADDI immediate {imm} out of 16-bit signed range")
    opcode = ADDI_OPCODE['ADDI']
    return (opcode << 26) | (rs << 21) | (rt << 16) | (imm & 0xFFFF)


def encode_jal(operands, labels, imem_depth=4096):
    # format: JAL label  (target is an absolute instruction address,
    # not an offset - unlike BEQ/BNE)
    target_label = operands.strip()
    if target_label not in labels:
        raise ValueError(f"Unknown label '{target_label}'")
    target = labels[target_label]
    if not (0 <= target < imem_depth):
        raise ValueError(f"JAL target address {target} outside the "
                          f"{imem_depth}-word instruction memory")
    return (JAL_OPCODE << 26) | (target & 0x3FFFFFF)


def encode_jr(operands):
    # format: JR $rs  (PC = $rs's value, no register written)
    rs = reg_num(operands.strip())
    return (0 << 26) | (rs << 21) | (0 << 16) | (0 << 11) | (0 << 6) | JR_FUNCT


def encode_halt(operands):
    # format: HALT   (no operands - stops the FSM until reset)
    if operands.strip():
        raise ValueError(f"HALT takes no operands, got '{operands}'")
    return (HALT_OPCODE << 26)


def encode_multdiv(mnemonic, operands):
    # format: MULT $rs, $rt  /  DIV $rs, $rt  (no rd - result goes to HI/LO)
    ops = [o.strip() for o in operands.split(',')]
    if len(ops) != 2:
        raise ValueError(f"{mnemonic} expects '$rs, $rt', got '{operands}'")
    rs, rt = reg_num(ops[0]), reg_num(ops[1])
    funct = MULT_FUNCT if mnemonic == 'MULT' else DIV_FUNCT
    return (0 << 26) | (rs << 21) | (rt << 16) | (0 << 11) | (0 << 6) | funct


def encode_mfhilo(mnemonic, operands):
    # format: MFHI $rd  /  MFLO $rd  (no rs/rt - reads HI or LO)
    rd = reg_num(operands.strip())
    funct = MFHI_FUNCT if mnemonic == 'MFHI' else MFLO_FUNCT
    return (0 << 26) | (0 << 21) | (0 << 16) | (rd << 11) | (0 << 6) | funct


def assemble(text):
    instrs = parse_lines(text)
    labels = first_pass(instrs)

    results = []
    for addr, (mnemonic, label, operands, raw) in enumerate(instrs):
        if mnemonic in RTYPE_OPS:
            code = encode_rtype(mnemonic, operands)
        elif mnemonic in BRANCH_OPCODE:
            code = encode_branch(mnemonic, operands, addr, labels)
        elif mnemonic in MEM_OPCODE:
            code = encode_mem(mnemonic, operands)
        elif mnemonic in ADDI_OPCODE:
            code = encode_addi(operands)
        elif mnemonic == 'JAL':
            code = encode_jal(operands, labels)
        elif mnemonic == 'JR':
            code = encode_jr(operands)
        elif mnemonic == 'HALT':
            code = encode_halt(operands)
        elif mnemonic in MULTDIV_OPS:
            code = encode_multdiv(mnemonic, operands)
        elif mnemonic in MFHILO_OPS:
            code = encode_mfhilo(mnemonic, operands)
        else:
            raise ValueError(f"Unknown instruction '{mnemonic}' in line: {raw.strip()}")
        results.append((addr, mnemonic, operands, code, raw.strip()))
    return results, labels


def parse_data(text):
    """Parse the .data section: one value per line, decimal or 0x-hex,
    optional 'label: value' form (label recorded but not yet used
    elsewhere - reserved for future symbolic LW/SW support)."""
    values = []
    labels = {}
    for raw in text.splitlines():
        line = strip_comment(raw).strip()
        if not line:
            continue
        m = re.match(r'^(\w+):\s*(.*)$', line)
        if m and m.group(2):
            labels[m.group(1)] = len(values)
            line = m.group(2).strip()
        elif m and not m.group(2):
            labels[m.group(1)] = len(values)
            continue
        value = int(line, 0)
        if not (-2**31 <= value <= 2**32 - 1):
            raise ValueError(f".data value {value} doesn't fit in 32 bits")
        values.append(value & 0xFFFFFFFF)
    return values, labels


def print_report(results, labels):
    print("Labels found:")
    for name, addr in labels.items():
        print(f"  {name:12s} -> address {addr}")
    print()
    print(f"{'Addr':>4}  {'Source':38s}  Hex")
    print("-" * 60)
    for addr, mnemonic, operands, code, raw in results:
        print(f"{addr:4d}  {raw:38s}  32'h{code:08X}")
    print()
    print(f"Program length: {len(results)} instructions")


def write_hex_file(codes, filename, depth, word_desc):
    """Writes plain hex, one word per line, no prefixes/suffixes -
    exactly what Verilog's $readmemh expects. Pads with zeros up to
    'depth' lines so unused addresses are always well-defined."""
    if len(codes) > depth:
        raise ValueError(f"{word_desc} has {len(codes)} words, exceeds "
                          f"the {depth}-word memory depth.")
    with open(filename, 'w') as f:
        for code in codes:
            f.write(f"{code:08X}\n")
        for _ in range(depth - len(codes)):
            f.write("00000000\n")
    print(f"Wrote {filename} ({len(codes)} real {word_desc}, "
          f"padded to {depth} words with zeros)")


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 assembler.py program.asm")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        full_text = f.read()

    instr_text, data_text = split_sections(full_text)

    results, labels = assemble(instr_text)
    print_report(results, labels)

    codes = [code for (_, _, _, code, _) in results]
    # AUTO-RUN mode never returns to IDLE on its own, so a program with
    # no explicit stop would run off the end into the zero-padding and
    # TRAP (opcode 0/funct 0 isn't a real R-type instruction). That's
    # harmless but pollutes illegal_opcode with "program finished"
    # events. Auto-append a HALT so every assembled program has a
    # clean, deliberate stop unless the user already wrote one.
    if not results or results[-1][1] != 'HALT':
        codes.append(encode_halt(''))
        print("(No trailing HALT found in source - auto-appended one "
              "at the end of the program.)")
        print()

    write_hex_file(codes, "program.hex", depth=4096, word_desc="instructions")

    data_values, data_labels = parse_data(data_text)
    if data_labels:
        print()
        print("Data labels found:")
        for name, addr in data_labels.items():
            print(f"  {name:12s} -> memory[{addr}]")
    print()
    write_hex_file(data_values, "data.hex", depth=512, word_desc="data words")