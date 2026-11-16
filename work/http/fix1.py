import pathlib

root = pathlib.Path(r'C:\Users\1234.DESKTOP-KICPMJN\Downloads\ms[r\rsharp')

p = root / 'modules/http/quic_frame.rsx'
s = p.read_text(encoding='utf-8')
s = s.replace('fn qf_need(r: &QF, upto: i64) -> i32 {', 'fn qf_need(r: &mut QF, upto: i64) -> i32 {')
p.write_text(s, encoding='utf-8', newline='\n')

t = root / 'work/http/t_quicframe.rsx'
s = t.read_text(encoding='utf-8')
s = s.replace('qf_next(&r)', 'qf_next(&mut r)')
t.write_text(s, encoding='utf-8', newline='\n')
print('ok')
