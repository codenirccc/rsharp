import struct
import sys

p = sys.argv[1]
d = open(p, "rb").read()
pe = struct.unpack_from("<I", d, 0x3C)[0]
nsec = struct.unpack_from("<H", d, pe + 6)[0]
optsz = struct.unpack_from("<H", d, pe + 20)[0]
o = pe + 24
imp_rva, imp_sz = struct.unpack_from("<II", d, o + 112 + 8)
s = o + optsz
secs = []
for i in range(nsec):
    name = d[s:s + 8].rstrip(b"\0").decode()
    vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", d, s + 8)
    secs.append((name, vsize, vaddr, rawsize, rawptr))
    s += 40
print(secs)


def off(rva):
    for name, vsize, vaddr, rawsize, rawptr in secs:
        if vaddr <= rva < vaddr + max(vsize, rawsize):
            return rawptr + (rva - vaddr)
    return None


def u32(rva):
    return struct.unpack_from("<I", d, off(rva))[0]


def u64(rva):
    return struct.unpack_from("<Q", d, off(rva))[0]


def cstr(rva):
    p = off(rva)
    e = d.index(b"\0", p)
    return d[p:e].decode()


print("descriptor at %x" % imp_rva)
oft = u32(imp_rva)
name = u32(imp_rva + 12)
ft = u32(imp_rva + 16)
print("  OFT %x Name %x FT %x -> %s" % (oft, name, ft, cstr(name)))
i = 0
while True:
    t = u64(oft + 8 * i)
    if t == 0:
        break
    print("  INT[%d] %x hint %d name %s" % (i, t, struct.unpack_from("<H", d, off(t))[0], cstr(t + 2)))
    i += 1
i = 0
while True:
    t = u64(ft + 8 * i)
    if t == 0:
        break
    print("  IAT[%d] %x" % (i, t))
    i += 1
