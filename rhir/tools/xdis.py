import struct
import sys

import capstone

p = sys.argv[1]
d = open(p, "rb").read()
pe = struct.unpack_from("<I", d, 0x3C)[0]
nsec = struct.unpack_from("<H", d, pe + 6)[0]
optsz = struct.unpack_from("<H", d, pe + 20)[0]
o = pe + 24
entry = struct.unpack_from("<I", d, o + 16)[0]
imagebase = struct.unpack_from("<Q", d, o + 24)[0]
s = o + optsz
for i in range(nsec):
    name = d[s:s + 8].rstrip(b"\0").decode()
    vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", d, s + 8)
    if name == ".text":
        code = d[rawptr:rawptr + vsize]
        base = imagebase + vaddr
    s += 40

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = False
for ins in md.disasm(code, base):
    mark = "  <== entry" if ins.address == imagebase + entry else ""
    print("%08x  %-24s %s %s%s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str, mark))
