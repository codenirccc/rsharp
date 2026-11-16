pub mod cfg;
pub mod dom;
pub mod emit;
pub mod ir;
pub mod isel;
pub mod mem2reg;
pub mod mir;
pub mod opt;
pub mod pe;
pub mod regalloc;
pub mod text;

use std::collections::HashMap;

use ir::Module;

pub fn build_module(module: &Module) -> Result<Vec<u8>, String> {
    let mut m = module.clone();
    for f in m.funcs.iter_mut() {
        opt::run(f);
    }

    let mut extern_names: Vec<String> = m.externs.iter().map(|e| e.name.clone()).collect();
    if !extern_names.iter().any(|n| n == "ExitProcess") {
        extern_names.push("ExitProcess".to_string());
    }

    let stub = emit::entry_stub();
    let mut text: Vec<u8> = Vec::new();
    let mut fixups: Vec<(usize, String)> = stub
        .abs
        .iter()
        .map(|(p, n)| (*p, n.clone()))
        .collect();
    let mut calls: Vec<(usize, String)> = stub
        .calls
        .iter()
        .map(|(p, n)| (*p, n.clone()))
        .collect();
    text.extend_from_slice(&stub.bytes);

    let mut symbols: HashMap<String, usize> = HashMap::new();
    for f in &m.funcs {
        if symbols.contains_key(&f.name) {
            return Err(format!("duplicate function '{}'", f.name));
        }
        while text.len() % 16 != 0 {
            text.push(0xCC);
        }
        let base = text.len();
        symbols.insert(f.name.clone(), base);
        let mf = isel::lower(f, &m)?;
        let alloc = regalloc::run(&mf, f.values.len(), mf.slots);
        let code = emit::function(&mf, &alloc, &extern_names);
        for (p, t) in &code.calls {
            calls.push((base + p, t.clone()));
        }
        for (p, n) in &code.abs {
            fixups.push((base + p, n.clone()));
        }
        text.extend_from_slice(&code.bytes);
    }

    for (pos, target) in &calls {
        let dest = match symbols.get(target) {
            Some(d) => *d,
            None => return Err(format!("undefined function '{}'", target)),
        };
        let rel = dest as i64 - (*pos as i64 + 4);
        if rel < i32::MIN as i64 || rel > i32::MAX as i64 {
            return Err(format!("call to '{}' is out of range", target));
        }
        text[*pos..*pos + 4].copy_from_slice(&(rel as i32).to_le_bytes());
    }

    let globals: Vec<(String, Vec<u8>)> = m
        .globals
        .iter()
        .map(|g| (g.name.clone(), g.bytes.clone()))
        .collect();

    let lay = pe::layout(text.len() as u32, &extern_names, &globals);

    for (pos, name) in &fixups {
        let va = lay
            .iat
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, r)| pe::IMAGE_BASE + *r as u64)
            .or_else(|| {
                lay.globals
                    .iter()
                    .find(|(n, _)| n == name)
                    .map(|(_, r)| pe::IMAGE_BASE + *r as u64)
            })
            .ok_or_else(|| format!("undefined symbol '{}'", name))?;
        if *pos + 8 > text.len() {
            return Err("internal: fixup outside .text".to_string());
        }
        text[*pos..*pos + 8].copy_from_slice(&va.to_le_bytes());
    }

    Ok(pe::image(&text, 0, &lay))
}

pub fn assemble(src: &str) -> Result<Vec<u8>, String> {
    let m = text::parse(src)?;
    build_module(&m)
}

pub fn emit_ir(src: &str) -> Result<String, String> {
    let mut m = text::parse(src)?;
    for f in m.funcs.iter_mut() {
        opt::run(f);
    }
    Ok(text::print_module(&m))
}

pub fn parse(src: &str) -> Result<Module, String> {
    let mut m = text::parse(src)?;
    for f in m.funcs.iter_mut() {
        opt::run(f);
    }
    Ok(m)
}

pub fn entry_offset() -> u32 {
    0
}
