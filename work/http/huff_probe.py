from hpack.huffman_constants import REQUEST_CODES as C, REQUEST_CODES_LENGTH as L

nodes = [[-1, -1]]
maxlen = 0
for i in range(257):
    cur = 0
    for b in range(L[i] - 1, -1, -1):
        bit = (C[i] >> b) & 1
        if nodes[cur][bit] < 0:
            nodes[cur][bit] = len(nodes)
            nodes.append([-1, -1])
        cur = nodes[cur][bit]
    maxlen = max(maxlen, L[i])
print('nodes', len(nodes), 'maxlen', maxlen)

print('leaves', sum(1 for n in nodes if n[0] < 0 and n[1] < 0))
