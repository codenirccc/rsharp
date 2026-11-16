import struct
import sys

REQ = 0x80000000
NAMES = {0xC: 'load_dylib', 0xD: 'id_dylib', 0x18E: 'load_weak_dylib',
         0x1F: 'reexport_dylib', 0x18: 'load_upward_dylib', 0x23: 'lazy_load_dylib'}
SEG = 0x19
SYMTAB = 0x2
DYSYMTAB = 0xB
MAIN = 0x28

d = open(sys.argv[1], 'rb').read()
magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _res = struct.unpack_from('<IiiIIIII', d, 0)
if magic != 0xFEEDFACF:
    sys.exit('not a 64-bit macho')
dylibs = {}
o = 32
symoff = nsyms = stroff = None
dysym = None
entry = None
segs = []
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', d, o)
    base = cmd & ~REQ
    if base in NAMES:
        nameoff, = struct.unpack_from('<I', d, o + 8)
        name = d[o + nameoff:o + size].split(b'\0')[0].decode('utf-8', 'replace')
        dylibs[len(dylibs) + 1] = name
    elif base == SEG:
        segname = d[o + 8:o + 24].split(b'\0')[0].decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', d, o + 24)
        segs.append((segname, vmaddr, vmsize, fileoff, filesize))
    elif base == SYMTAB:
        symoff, nsyms, stroff, strsize = struct.unpack_from('<IIII', d, o + 8)
    elif base == DYSYMTAB:
        f = struct.unpack_from('<18I', d, o + 8)
        dysym = (f[4], f[5])
    elif base == MAIN:
        entry, = struct.unpack_from('<Q', d, o + 8)
    o += size

print('file %s  size=%d  cmds=%d  entry=%s' % (sys.argv[1], len(d), ncmds, entry))
for s in segs:
    print('  seg %-10s vm=%#x size=%#x file=%#x+%#x' % s)
for k in sorted(dylibs):
    print('  dylib %d  %s' % (k, dylibs[k]))

names = []
if dysym and symoff is not None:
    iundef, nundef = dysym
    for i in range(nundef):
        strx, ntype, nsect, ndesc, nval = struct.unpack_from('<IBBHQ', d, symoff + (iundef + i) * 16)
        s = d[stroff + strx:d.index(b'\0', stroff + strx)].decode('utf-8', 'replace')
        names.append((s, ndesc >> 8))
    names.sort()
print('  undefined=%d' % len(names))
for s, lib in names:
    print('    %-26s <- %s' % (s, dylibs.get(lib, 'ordinal %d' % lib)))
