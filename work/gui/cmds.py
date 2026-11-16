import struct
import sys

d = open(sys.argv[1], 'rb').read()
ncmds = struct.unpack_from('<I', d, 16)[0]
o = 32
for i in range(ncmds):
    cmd, size = struct.unpack_from('<II', d, o)
    print('%2d  cmd=%#x size=%d' % (i, cmd, size))
    o += size
