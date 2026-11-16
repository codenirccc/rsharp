mod ast;
mod lexer;
mod parser;
mod sexpr;

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

fn expand_includes(
    path: &Path,
    depth: usize,
    seen: &mut HashSet<PathBuf>,
    out: &mut String,
) -> Result<(), String> {
    if depth > 16 {
        return Err(format!(
            "includes nested more than 16 deep, here at '{}'",
            path.display()
        ));
    }
    let canon = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    if !seen.insert(canon) {
        return Ok(());
    }
    let src = fs::read_to_string(path).map_err(|e| format!("cannot read '{}': {}", path.display(), e))?;
    let mut in_block = false;
    for line in src.lines() {
        if !in_block {
            let t = line.trim();
            if let Some(rest) = t.strip_prefix("include") {
                let rest = rest.trim_start();
                if let Some(inner) = rest.strip_prefix('"') {
                    if let Some(end) = inner.find('"') {
                        let name = &inner[..end];
                        let found = find_include(path, name).ok_or_else(|| {
                            if depth == 0 {
                                format!("cannot find include '{}'", name)
                            } else {
                                format!("{}: cannot find include '{}'", path.display(), name)
                            }
                        })?;
                        expand_includes(&found, depth + 1, seen, out)?;
                        if !out.ends_with('\n') {
                            out.push('\n');
                        }
                        continue;
                    }
                }
            }
        }
        in_block = block_comment_continues(line, in_block);
        out.push_str(line);
        out.push('\n');
    }
    Ok(())
}

fn block_comment_continues(line: &str, mut in_block: bool) -> bool {
    let b = line.as_bytes();
    let mut i = 0usize;
    let mut in_str = false;
    while i < b.len() {
        if in_block {
            if i + 1 < b.len() && b[i] == b'*' && b[i + 1] == b'/' {
                in_block = false;
                i += 2;
            } else {
                i += 1;
            }
            continue;
        }
        if in_str {
            if b[i] == b'\\' {
                i += 2;
                continue;
            }
            if b[i] == b'"' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if b[i] == b'"' {
            in_str = true;
            i += 1;
            continue;
        }
        if i + 1 < b.len() && b[i] == b'/' && b[i + 1] == b'/' {
            return false;
        }
        if i + 1 < b.len() && b[i] == b'/' && b[i + 1] == b'*' {
            in_block = true;
            i += 2;
            continue;
        }
        i += 1;
    }
    in_block
}

fn find_include(from: &Path, name: &str) -> Option<PathBuf> {
    let direct = from.parent().unwrap_or(Path::new(".")).join(name);
    if direct.is_file() {
        return Some(direct);
    }
    let mut dir = from.parent();
    while let Some(d) = dir {
        let p = d.join("lib").join(name);
        if p.is_file() {
            return Some(p);
        }
        dir = d.parent();
    }
    let p = PathBuf::from(name);
    if p.is_file() {
        return Some(p);
    }
    None
}

fn usage() -> ExitCode {
    eprintln!("rsc - R# front end");
    eprintln!("usage: rsc <file.rsx> [-o <file.rsi>]");
    eprintln!("       rsc --tokenize <file.rsx>");
    ExitCode::from(2)
}

struct Clock {
    on: bool,
    start: std::time::Instant,
    prev: std::time::Instant,
}

impl Clock {
    fn new() -> Clock {
        let now = std::time::Instant::now();
        Clock {
            on: std::env::var_os("RSC_TIME").is_some(),
            start: now,
            prev: now,
        }
    }

    fn stamp(&mut self, name: &str) {
        if !self.on {
            return;
        }
        let now = std::time::Instant::now();
        eprintln!(
            "rsc: {:<8} {:>7.2} ms  (cum {:>7.2})",
            name,
            now.duration_since(self.prev).as_secs_f64() * 1000.0,
            now.duration_since(self.start).as_secs_f64() * 1000.0
        );
        self.prev = now;
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();

    let mut input: Option<String> = None;
    let mut output: Option<String> = None;
    let mut dump_tokens = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-o" | "--output" => {
                if i + 1 >= args.len() {
                    return usage();
                }
                output = Some(args[i + 1].clone());
                i += 2;
            }
            "--tokenize" => {
                dump_tokens = true;
                i += 1;
            }
            "-h" | "--help" => return usage(),
            a if a.starts_with('-') => {
                eprintln!("rsc: unknown flag '{}'", a);
                return usage();
            }
            a => {
                if input.is_some() {
                    eprintln!("rsc: only one input file is supported");
                    return usage();
                }
                input = Some(a.to_string());
                i += 1;
            }
        }
    }

    let Some(path) = input else {
        return usage();
    };

    let mut clock = Clock::new();

    let seed = fs::metadata(&path).map(|m| m.len() as usize).unwrap_or(0);
    let mut src = String::with_capacity(seed + 1);
    let mut seen = HashSet::new();
    if let Err(e) = expand_includes(Path::new(&path), 0, &mut seen, &mut src) {
        eprintln!("rsc: {}: {}", path, e);
        return ExitCode::from(1);
    }
    clock.stamp("expand");

    let tokens = match lexer::tokenize(&src) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("rsc: {}: {}", path, e);
            return ExitCode::from(1);
        }
    };
    clock.stamp("lex");

    if dump_tokens {
        for t in &tokens {
            println!("{}:{}  {:?}", t.line, t.col, t.tok);
        }
        return ExitCode::SUCCESS;
    }

    let mut p = parser::Parser::new(tokens);
    let program = match p.parse_program() {
        Ok(prog) => prog,
        Err(e) => {
            eprintln!("rsc: {}: {}", path, e);
            return ExitCode::from(1);
        }
    };
    clock.stamp("parse");

    let ir = sexpr::emit_program(&program, src.len());
    clock.stamp("emit");

    match output {
        Some(out) => {
            if let Err(e) = fs::write(&out, ir) {
                eprintln!("rsc: cannot write '{}': {}", out, e);
                return ExitCode::from(1);
            }
        }
        None => print!("{}", ir),
    }
    clock.stamp("write");

    ExitCode::SUCCESS
}
