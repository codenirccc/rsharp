pub struct Layout {
    pub text_off: u32,
    pub rdata_rva: u32,
    pub rdata: Vec<u8>,
    pub iat: Vec<(String, u32)>,
    pub globals: Vec<(String, u32)>,
    pub import_dir: u32,
}

const FILE_ALIGN: u32 = 0x200;
const SECT_ALIGN: u32 = 0x1000;
const BASE: u64 = 0x1_4000_0000;
const HEADERS: u32 = 0x400;

pub const IMAGE_BASE: u64 = BASE;
pub const TEXT_RVA: u32 = SECT_ALIGN;

fn put16(v: &mut Vec<u8>, x: u16) {
    v.extend_from_slice(&x.to_le_bytes());
}

fn put32(v: &mut Vec<u8>, x: u32) {
    v.extend_from_slice(&x.to_le_bytes());
}

fn put64(v: &mut Vec<u8>, x: u64) {
    v.extend_from_slice(&x.to_le_bytes());
}

fn align_up(x: u32, a: u32) -> u32 {
    (x + a - 1) / a * a
}

fn pad(v: &mut Vec<u8>, to: u32) {
    while (v.len() as u32) < to {
        v.push(0);
    }
}

fn cstr(v: &mut Vec<u8>, s: &str) {
    v.extend_from_slice(s.as_bytes());
    v.push(0);
}

pub fn text_raw_size(text_vsize: u32) -> u32 {
    align_up(text_vsize.max(1), FILE_ALIGN)
}

pub fn layout(text_vsize: u32, externs: &[String], globals: &[(String, Vec<u8>)]) -> Layout {
    let text_off = HEADERS;
    let rdata_rva = TEXT_RVA + align_up(text_raw_size(text_vsize), SECT_ALIGN);

    let mut rd: Vec<u8> = Vec::new();

    put32(&mut rd, 0);
    put32(&mut rd, 0);
    put32(&mut rd, 0);
    put32(&mut rd, 0);
    put32(&mut rd, 0);
    put32(&mut rd, 0);
    put32(&mut rd, 0);
    put32(&mut rd, 0);
    put32(&mut rd, 0);
    put32(&mut rd, 0);
    let dir_off = 0u32;

    let thunk_n = externs.len() + 1;
    let int_off = rd.len() as u32;
    for _ in 0..thunk_n {
        put64(&mut rd, 0);
    }
    let iat_off = rd.len() as u32;
    for _ in 0..thunk_n {
        put64(&mut rd, 0);
    }

    let mut hint_off = Vec::new();
    for name in externs {
        while rd.len() % 2 != 0 {
            rd.push(0);
        }
        hint_off.push(rd.len() as u32);
        put16(&mut rd, 0);
        cstr(&mut rd, name);
    }
    let dll_off = rd.len() as u32;
    cstr(&mut rd, "KERNEL32.dll");

    while rd.len() % 8 != 0 {
        rd.push(0);
    }

    let int_rva = rdata_rva + int_off;
    let iat_rva = rdata_rva + iat_off;
    let dll_rva = rdata_rva + dll_off;
    let mut iat = Vec::new();
    for (i, name) in externs.iter().enumerate() {
        let h_rva = rdata_rva + hint_off[i] as u32;
        let p = int_off as usize + i * 8;
        rd[p..p + 8].copy_from_slice(&(h_rva as u64).to_le_bytes());
        let q = iat_off as usize + i * 8;
        rd[q..q + 8].copy_from_slice(&(h_rva as u64).to_le_bytes());
        iat.push((name.clone(), iat_rva + 8 * i as u32));
    }

    let d = dir_off as usize;
    rd[d..d + 4].copy_from_slice(&int_rva.to_le_bytes());
    rd[d + 12..d + 16].copy_from_slice(&dll_rva.to_le_bytes());
    rd[d + 16..d + 20].copy_from_slice(&iat_rva.to_le_bytes());

    let mut gmap = Vec::new();
    for (name, bytes) in globals {
        while rd.len() % 8 != 0 {
            rd.push(0);
        }
        let off = rd.len() as u32;
        rd.extend_from_slice(bytes);
        gmap.push((name.clone(), rdata_rva + off));
    }

    Layout {
        text_off,
        rdata_rva,
        rdata: rd,
        iat,
        globals: gmap,
        import_dir: rdata_rva + dir_off,
    }
}

pub fn image(text: &[u8], entry: u32, lay: &Layout) -> Vec<u8> {
    let text_vsize = text.len() as u32;
    let text_raw = text_raw_size(text_vsize);
    let rdata_vsize = lay.rdata.len() as u32;
    let rdata_raw = align_up(rdata_vsize.max(1), FILE_ALIGN);
    let rdata_off = lay.text_off + text_raw;
    let size_of_image = lay.rdata_rva + align_up(rdata_vsize.max(1), SECT_ALIGN);
    let entry_rva = TEXT_RVA + entry;

    let size_of_headers = lay.text_off;
    let mut out: Vec<u8> = Vec::new();

    out.extend_from_slice(&[0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00]);
    out.extend_from_slice(&[0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00]);
    out.extend_from_slice(&[0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    out.extend_from_slice(&[0x40, 0x00, 0x00, 0x00]);
    pad(&mut out, 0x3C);
    put32(&mut out, 0x80);

    let mut stub: Vec<u8> = Vec::new();
    stub.extend_from_slice(b"This program cannot be run in DOS mode.\r\r\n$");
    while stub.len() % 8 != 0 {
        stub.push(0);
    }
    out.extend_from_slice(&stub);
    while out.len() % 8 != 0 {
        out.push(0);
    }
    let pe_off = out.len() as u32;

    out.extend_from_slice(b"PE\0\0");
    put16(&mut out, 0x8664);
    put16(&mut out, 2);
    put32(&mut out, 0);
    put32(&mut out, 0);
    put32(&mut out, 0);
    put16(&mut out, 0xF0);
    put16(&mut out, 0x0022);

    put16(&mut out, 0x020B);
    out.push(14);
    out.push(0);
    put32(&mut out, text_raw.max(text_vsize));
    put32(&mut out, rdata_raw);
    put32(&mut out, 0);
    put32(&mut out, entry_rva);
    put32(&mut out, TEXT_RVA);
    put64(&mut out, BASE);
    put32(&mut out, SECT_ALIGN);
    put32(&mut out, FILE_ALIGN);
    put16(&mut out, 6);
    put16(&mut out, 0);
    put16(&mut out, 0);
    put16(&mut out, 0);
    put16(&mut out, 6);
    put16(&mut out, 0);
    put32(&mut out, 0);
    put32(&mut out, size_of_image);
    put32(&mut out, size_of_headers);
    put32(&mut out, 0);
    put16(&mut out, 2);
    put16(&mut out, 0x8100);
    put64(&mut out, 0x10_0000);
    put64(&mut out, 0x1000);
    put64(&mut out, 0x10_0000);
    put64(&mut out, 0x1000);
    put32(&mut out, 0);
    put32(&mut out, 16);

    for i in 0..16 {
        if i == 1 {
            put32(&mut out, lay.import_dir);
            put32(&mut out, 40);
        } else {
            put32(&mut out, 0);
            put32(&mut out, 0);
        }
    }

    out.extend_from_slice(b".text\0\0\0");
    put32(&mut out, text_vsize);
    put32(&mut out, TEXT_RVA);
    put32(&mut out, text_raw);
    put32(&mut out, lay.text_off);
    put32(&mut out, 0);
    put32(&mut out, 0);
    put16(&mut out, 0);
    put16(&mut out, 0);
    put32(&mut out, 0x6000_0020);

    out.extend_from_slice(b".rdata\0\0");
    put32(&mut out, rdata_vsize);
    put32(&mut out, lay.rdata_rva);
    put32(&mut out, rdata_raw);
    put32(&mut out, rdata_off);
    put32(&mut out, 0);
    put32(&mut out, 0);
    put16(&mut out, 0);
    put16(&mut out, 0);
    put32(&mut out, 0xC000_0040);

    pad(&mut out, size_of_headers);
    out.extend_from_slice(text);
    pad(&mut out, size_of_headers + text_raw);
    out.extend_from_slice(&lay.rdata);
    pad(&mut out, rdata_off + rdata_raw);

    let pe_slot = 0x3Cusize;
    let pe_fix = pe_off;
    out[pe_slot..pe_slot + 4].copy_from_slice(&pe_fix.to_le_bytes());
    out
}
