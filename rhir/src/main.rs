use std::env;
use std::fs;
use std::process::ExitCode;

fn usage() -> String {
    "usage: rhirc <input.rhir> [-o output.exe] [--emit-ir]".to_string()
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        eprintln!("{}", usage());
        return ExitCode::from(2);
    }

    let mut input: Option<String> = None;
    let mut output: Option<String> = None;
    let mut emit_ir = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-o" | "--output" => {
                i += 1;
                match args.get(i) {
                    Some(p) => output = Some(p.clone()),
                    None => {
                        eprintln!("rhirc: -o needs a path");
                        return ExitCode::from(2);
                    }
                }
            }
            "--emit-ir" => emit_ir = true,
            "-h" | "--help" => {
                println!("{}", usage());
                return ExitCode::SUCCESS;
            }
            other => {
                if input.is_some() {
                    eprintln!("rhirc: unexpected argument '{}'", other);
                    return ExitCode::from(2);
                }
                input = Some(other.to_string());
            }
        }
        i += 1;
    }

    let input = match input {
        Some(p) => p,
        None => {
            eprintln!("{}", usage());
            return ExitCode::from(2);
        }
    };

    let src = match fs::read_to_string(&input) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("rhirc: cannot read {}: {}", input, e);
            return ExitCode::FAILURE;
        }
    };

    if emit_ir {
        return match rhir::emit_ir(&src) {
            Ok(s) => {
                print!("{}", s);
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("rhirc: {}", e);
                ExitCode::FAILURE
            }
        };
    }

    let bytes = match rhir::assemble(&src) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("rhirc: {}", e);
            return ExitCode::FAILURE;
        }
    };

    let out = output.unwrap_or_else(|| {
        let p = std::path::Path::new(&input);
        p.with_extension("exe").to_string_lossy().to_string()
    });

    match fs::write(&out, &bytes) {
        Ok(()) => {
            println!("rhirc: wrote {} ({} bytes)", out, bytes.len());
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("rhirc: cannot write {}: {}", out, e);
            ExitCode::FAILURE
        }
    }
}
