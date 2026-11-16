type reg = int

let rax = 0
let rcx = 1
let rdx = 2
let rbx = 3
let rsp = 4
let rbp = 5
let rsi = 6
let rdi = 7
let r8 = 8
let r9 = 9
let r10 = 10
let r11 = 11
let r12 = 12
let r13 = 13
let r14 = 14
let r15 = 15

type code = { buf : Buffer.t }

let create () = { buf = Buffer.create 8192 }
let pos c = Buffer.length c.buf
let raw c = Buffer.contents c.buf
let b c v = Buffer.add_char c.buf (Char.chr (v land 0xff))

let u32 c v =
  b c v;
  b c (v lsr 8);
  b c (v lsr 16);
  b c (v lsr 24)

let imm64 c (v : int64) =
  u32 c (Int64.to_int (Int64.logand v 0xFFFFFFFFL));
  u32 c (Int64.to_int (Int64.shift_right_logical v 32))

let rex c ~w ~r ~x ~bb =
  let v = 0x40 lor (if w then 8 else 0) lor ((r lsr 3) lsl 2) lor ((x lsr 3) lsl 1) lor (bb lsr 3) in
  if v <> 0x40 then b c v

let modrm c mod_ reg rm = b c ((mod_ lsl 6) lor ((reg land 7) lsl 3) lor (rm land 7))

let mem c ~reg ~base ~disp =
  let rm = base land 7 in
  let mod_ = if disp = 0 && rm <> 5 then 0 else if disp >= -128 && disp <= 127 then 1 else 2 in
  modrm c mod_ reg rm;
  if rm = 4 then b c 0x24;
  if mod_ = 1 then b c (disp land 0xff) else if mod_ = 2 then u32 c disp

let riprel c ~reg ~disp =
  modrm c 0 reg 5;
  u32 c disp

let rr c ~reg ~rm = modrm c 3 reg rm

let mov_rr c dst src =
  rex c ~w:false ~r:src ~x:0 ~bb:dst;
  b c 0x89;
  rr c ~reg:src ~rm:dst

let mov_rr64 c dst src =
  rex c ~w:true ~r:src ~x:0 ~bb:dst;
  b c 0x89;
  rr c ~reg:src ~rm:dst

let mov_ri c dst v =
  rex c ~w:true ~r:0 ~x:0 ~bb:dst;
  b c (0xB8 lor (dst land 7));
  imm64 c v

let mov_ri64 c dst v = mov_ri c dst (Int64.of_int v)

let mov_ri32 c dst v =
  b c (0xB8 lor (dst land 7));
  u32 c v

let alu c op dst src =
  rex c ~w:true ~r:src ~x:0 ~bb:dst;
  b c op;
  rr c ~reg:src ~rm:dst

let add_rr c dst src = alu c 0x01 dst src
let sub_rr c dst src = alu c 0x29 dst src
let and_rr c dst src = alu c 0x21 dst src
let or_rr c dst src = alu c 0x09 dst src
let xor_rr c dst src = alu c 0x31 dst src
let cmp_rr c dst src = alu c 0x39 dst src
let test_rr c dst src = alu c 0x85 dst src

let imul_rr c dst src =
  rex c ~w:true ~r:dst ~x:0 ~bb:src;
  b c 0x0F;
  b c 0xAF;
  rr c ~reg:dst ~rm:src

let unary c op reg =
  rex c ~w:true ~r:0 ~x:0 ~bb:reg;
  b c 0xF7;
  modrm c 3 op reg

let neg_rr c r = unary c 3 r
let not_rr c r = unary c 2 r
let idiv_rr c r = unary c 7 r
let div_rr c r = unary c 6 r
let cqo c = b c 0x48; b c 0x99

let shift_cl c op r =
  rex c ~w:true ~r:0 ~x:0 ~bb:r;
  b c 0xD3;
  modrm c 3 op r

let shl_cl c r = shift_cl c 4 r
let shr_cl c r = shift_cl c 5 r
let sar_cl c r = shift_cl c 7 r

let movzx8 c dst rmreg =
  rex c ~w:true ~r:dst ~x:0 ~bb:rmreg;
  b c 0x0F;
  b c 0xB6;
  rr c ~reg:dst ~rm:rmreg

let movsx8 c dst rmreg =
  rex c ~w:true ~r:dst ~x:0 ~bb:rmreg;
  b c 0x0F;
  b c 0xBE;
  rr c ~reg:dst ~rm:rmreg

let movzx16 c dst rmreg =
  rex c ~w:true ~r:dst ~x:0 ~bb:rmreg;
  b c 0x0F;
  b c 0xB7;
  rr c ~reg:dst ~rm:rmreg

let movsx16 c dst rmreg =
  rex c ~w:true ~r:dst ~x:0 ~bb:rmreg;
  b c 0x0F;
  b c 0xBF;
  rr c ~reg:dst ~rm:rmreg

let movsxd c dst rmreg =
  rex c ~w:true ~r:dst ~x:0 ~bb:rmreg;
  b c 0x63;
  rr c ~reg:dst ~rm:rmreg

let load64 c dst base disp =
  rex c ~w:true ~r:dst ~x:0 ~bb:base;
  b c 0x8B;
  mem c ~reg:dst ~base ~disp

let load32 c dst base disp =
  rex c ~w:false ~r:dst ~x:0 ~bb:base;
  b c 0x8B;
  mem c ~reg:dst ~base ~disp

let load16 c dst base disp =
  b c 0x66;
  rex c ~w:false ~r:dst ~x:0 ~bb:base;
  b c 0x8B;
  mem c ~reg:dst ~base ~disp

let load8 c dst base disp =
  rex c ~w:false ~r:dst ~x:0 ~bb:base;
  b c 0x8A;
  mem c ~reg:dst ~base ~disp

let store64 c src base disp =
  rex c ~w:true ~r:src ~x:0 ~bb:base;
  b c 0x89;
  mem c ~reg:src ~base ~disp

let store32 c src base disp =
  rex c ~w:false ~r:src ~x:0 ~bb:base;
  b c 0x89;
  mem c ~reg:src ~base ~disp

let store16 c src base disp =
  b c 0x66;
  rex c ~w:false ~r:src ~x:0 ~bb:base;
  b c 0x89;
  mem c ~reg:src ~base ~disp

let store8 c src base disp =
  rex c ~w:false ~r:src ~x:0 ~bb:base;
  b c 0x88;
  mem c ~reg:src ~base ~disp

let lea c dst base disp =
  rex c ~w:true ~r:dst ~x:0 ~bb:base;
  b c 0x8D;
  mem c ~reg:dst ~base ~disp

let mov_mem_imm32 c base disp v =
  rex c ~w:true ~r:0 ~x:0 ~bb:base;
  b c 0xC7;
  mem c ~reg:0 ~base ~disp;
  u32 c v

let setcc c cc r = b c 0x0F; b c (0x90 lor cc); rr c ~reg:0 ~rm:r

let push c r =
  if r >= 8 then b c 0x41;
  b c (0x50 lor (r land 7))

let pop c r =
  if r >= 8 then b c 0x41;
  b c (0x58 lor (r land 7))

let ret c = b c 0xC3
let nop c = b c 0x90
let rep_movsb c = b c 0xF3; b c 0xA4

let jmp c = b c 0xE9; u32 c 0
let jcc c cc = b c 0x0F; b c (0x80 lor cc); u32 c 0
let call_rel c = b c 0xE8; u32 c 0
let call_reg c r =
  rex c ~w:false ~r:0 ~x:0 ~bb:r;
  b c 0xFF;
  rr c ~reg:2 ~rm:r
let call_ind c = rex c ~w:false ~r:0 ~x:0 ~bb:0; b c 0xFF; riprel c ~reg:2 ~disp:0
let lea_rip c dst = rex c ~w:true ~r:dst ~x:0 ~bb:0; b c 0x8D; riprel c ~reg:dst ~disp:0

let sse1 c pfx op reg rmreg =
  if pfx <> 0 then b c pfx;
  rex c ~w:false ~r:reg ~x:0 ~bb:rmreg;
  b c 0x0F;
  b c op;
  rr c ~reg ~rm:rmreg

let sse1m c pfx op reg base disp =
  if pfx <> 0 then b c pfx;
  rex c ~w:false ~r:reg ~x:0 ~bb:base;
  b c 0x0F;
  b c op;
  mem c ~reg ~base ~disp

let movsd_rr c dst src = sse1 c 0xF2 0x10 dst src
let addsd_rr c dst src = sse1 c 0xF2 0x58 dst src
let subsd_rr c dst src = sse1 c 0xF2 0x5C dst src
let mulsd_rr c dst src = sse1 c 0xF2 0x59 dst src
let divsd_rr c dst src = sse1 c 0xF2 0x5E dst src
let ucomisd_rr c dst src = b c 0x66; sse1 c 0x00 0x2E dst src
let xorpd_rr c dst src = b c 0x66; sse1 c 0x00 0x57 dst src
let pxor_rr c dst src = b c 0x66; sse1 c 0x00 0xEF dst src

let movss_rr c dst src = sse1 c 0xF3 0x10 dst src
let addss_rr c dst src = sse1 c 0xF3 0x58 dst src
let subss_rr c dst src = sse1 c 0xF3 0x5C dst src
let mulss_rr c dst src = sse1 c 0xF3 0x59 dst src
let divss_rr c dst src = sse1 c 0xF3 0x5E dst src
let ucomiss_rr c dst src = sse1 c 0x00 0x2E dst src

let movsd_load c xmm base disp = sse1m c 0xF2 0x10 xmm base disp
let movsd_store c xmm base disp = sse1m c 0xF2 0x11 xmm base disp
let movss_load c xmm base disp = sse1m c 0xF3 0x10 xmm base disp
let movss_store c xmm base disp = sse1m c 0xF3 0x11 xmm base disp

let cvtsd2ss c dst src = sse1 c 0xF2 0x5A dst src
let cvtss2sd c dst src = sse1 c 0xF3 0x5A dst src

let cvtsi2sd c xmm gpr =
  b c 0xF2;
  rex c ~w:true ~r:xmm ~x:0 ~bb:gpr;
  b c 0x0F;
  b c 0x2A;
  rr c ~reg:xmm ~rm:gpr

let cvtsi2ss c xmm gpr =
  b c 0xF3;
  rex c ~w:true ~r:xmm ~x:0 ~bb:gpr;
  b c 0x0F;
  b c 0x2A;
  rr c ~reg:xmm ~rm:gpr

let cvttsd2si c gpr xmm =
  b c 0xF2;
  rex c ~w:true ~r:gpr ~x:0 ~bb:xmm;
  b c 0x0F;
  b c 0x2C;
  rr c ~reg:gpr ~rm:xmm

let cvttss2si c gpr xmm =
  b c 0xF3;
  rex c ~w:true ~r:gpr ~x:0 ~bb:xmm;
  b c 0x0F;
  b c 0x2C;
  rr c ~reg:gpr ~rm:xmm

let movq_xmm_gpr c xmm gpr =
  b c 0x66;
  rex c ~w:true ~r:xmm ~x:0 ~bb:gpr;
  b c 0x0F;
  b c 0x6E;
  rr c ~reg:xmm ~rm:gpr

let movq_gpr_xmm c gpr xmm =
  b c 0x66;
  rex c ~w:true ~r:gpr ~x:0 ~bb:xmm;
  b c 0x0F;
  b c 0x7E;
  rr c ~reg:gpr ~rm:xmm

let movsx8_m c dst base disp =
  rex c ~w:true ~r:dst ~x:0 ~bb:base;
  b c 0x0F;
  b c 0xBE;
  mem c ~reg:dst ~base ~disp

let movzx8_m c dst base disp =
  rex c ~w:true ~r:dst ~x:0 ~bb:base;
  b c 0x0F;
  b c 0xB6;
  mem c ~reg:dst ~base ~disp

let movsx16_m c dst base disp =
  rex c ~w:true ~r:dst ~x:0 ~bb:base;
  b c 0x0F;
  b c 0xBF;
  mem c ~reg:dst ~base ~disp

let movzx16_m c dst base disp =
  rex c ~w:true ~r:dst ~x:0 ~bb:base;
  b c 0x0F;
  b c 0xB7;
  mem c ~reg:dst ~base ~disp

let movsxd_m c dst base disp =
  rex c ~w:true ~r:dst ~x:0 ~bb:base;
  b c 0x63;
  mem c ~reg:dst ~base ~disp

let sub_rsp_imm32 c v =
  b c 0x48;
  b c 0x81;
  b c 0xEC;
  u32 c v

let and_rsp_imm8 c v =
  b c 0x48;
  b c 0x83;
  b c 0xE4;
  b c (v land 0xff)

let mov_al_imm8 c v =
  b c 0xB0;
  b c (v land 0xff)

let rep_stosb c =
  b c 0xF3;
  b c 0xAA

let hlt c = b c 0xF4
let ud2 c = b c 0x0F; b c 0x0B
let syscall c = b c 0x0F; b c 0x05
let touch_rax c = b c 0xF6; b c 0x00; b c 0x00

let patch32 (buf : Bytes.t) at v =
  Bytes.set buf at (Char.chr (v land 0xff));
  Bytes.set buf (at + 1) (Char.chr ((v lsr 8) land 0xff));
  Bytes.set buf (at + 2) (Char.chr ((v lsr 16) land 0xff));
  Bytes.set buf (at + 3) (Char.chr ((v lsr 24) land 0xff))
