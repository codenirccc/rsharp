import struct
import sys

p = sys.argv[1]
d = open(p, "rb").read()
print("size", len(d))
print("mz", d[:2], "lfanew", hex(struct.unpack_from("<I", d, 0x3C)[0]))
pe = struct.unpack_from("<I", d, 0x3C)[0]
print("sig", d[pe:pe + 4])
machine, nsec, _, _, _, optsz, chars = struct.unpack_from("<HHIIIHH", d, pe + 4)
print("machine %x nsec %d optsz %x chars %x" % (machine, nsec, optsz, chars))
o = pe + 24
magic = struct.unpack_from("<H", d, o)[0]
print("magic %x" % magic)
(entry, basecode) = struct.unpack_from("<II", d, o + 16)
imagebase = struct.unpack_from("<Q", d, o + 24)[0]
secalign, filealign = struct.unpack_from("<II", d, o + 32)
sizeimage, sizeheaders = struct.unpack_from("<II", d, o + 56)
subsystem = struct.unpack_from("<H", d, o + 68)[0]
print("entry %x basecode %x imagebase %x secalign %x filealign %x sizeimage %x sizeheaders %x subsys %d"
      % (entry, basecode, imagebase, secalign, filealign, sizeimage, sizeheaders, subsystem))
nrva = struct.unpack_from("<I", d, o + 108)[0]
print("nrva", nrva)
imp_rva, imp_sz = struct.unpack_from("<II", d, o + 112 + 8)
print("import dir rva %x size %x" % (imp_rva, imp_sz))
s = o + optsz
for i in range(nsec):
    name = d[s:s + 8].rstrip(b"\0").decode()
    vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", d, s + 8)
    print("sect %s vsize %x vaddr %x rawsize %x rawptr %x" % (name, vsize, vaddr, rawsize, rawptr))
    s += 40
