mod fsutil;
mod json;
mod lock;
mod manifest;
mod project;
mod registry;
mod resolve;
mod semver;
mod sha256;

use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use lock::Lock;
use manifest::Manifest;
use project::{BuildError, InstallReport, Project};
use registry::Registry;
use resolve::resolve;
use semver::{Range, Version};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    match dispatch(&args) {
        Ok(code) => ExitCode::from(code),
        Err(e) => {
            eprintln!("cdc: {}", e);
            ExitCode::FAILURE
        }
    }
}

fn dispatch(args: &[String]) -> Result<u8, String> {
    let Some(cmd) = args.first() else {
        usage();
        return Ok(2);
    };
    let rest = &args[1..];
    match cmd.as_str() {
        "new" => cmd_new(rest),
        "init" => cmd_init(rest),
        "install" => cmd_install(rest),
        "add" => cmd_add(rest),
        "remove" => cmd_remove(rest),
        "build" => cmd_build(rest),
        "run" => cmd_run(rest),
        "publish" => cmd_publish(rest),
        "search" => cmd_search(rest),
        "tree" => cmd_tree(rest),
        "help" | "-h" | "--help" => {
            usage();
            Ok(0)
        }
        "version" | "-v" | "--version" => {
            println!("cdc {}", env!("CARGO_PKG_VERSION"));
            Ok(0)
        }
        other => Err(format!("unknown command '{}'; try cdc help", other)),
    }
}

fn usage() {
    println!("cdc {} - package manager for R#", env!("CARGO_PKG_VERSION"));
    println!();
    println!("usage: cdc <command> [options]");
    println!();
    println!("  new <name> [--lib]        create a package in ./<name>");
    println!("  init [--name <name>]      create cdc.json in the current directory");
    println!("  install                   resolve dependencies and fill cdc_modules/");
    println!("  add <name>[@<range>]      add a dependency, then install");
    println!("  remove <name>             drop a dependency, then install");
    println!("  build [-t <target>] [-o <file>]");
    println!("                            merge packages and build this one");
    println!("  run [-t <target>] [-- args...]");
    println!("                            build, then run");
    println!("  publish [--force]         copy this package into the registry");
    println!("  search [term]             list registry packages");
    println!("  tree                      print the resolved dependency tree");
    println!();
    println!("targets: windows (PE32+), macos (Mach-O). the host is the default.");
    println!("registry: $CDC_REGISTRY, else ~/.cdc-registry");
}

fn host_target() -> &'static str {
    if cfg!(windows) {
        "windows"
    } else {
        "macos"
    }
}

fn normalize_target(s: &str) -> Result<&'static str, String> {
    match s.to_ascii_lowercase().as_str() {
        "windows" | "win" | "win64" | "pe" => Ok("windows"),
        "macos" | "mac" | "darwin" | "osx" | "macho" => Ok("macos"),
        other => Err(format!(
            "unknown target '{}'; use windows or macos",
            other
        )),
    }
}

fn take(args: &[String], i: &mut usize, flag: &str) -> Result<String, String> {
    *i += 1;
    args.get(*i)
        .cloned()
        .ok_or_else(|| format!("{} needs a value", flag))
}

fn print_report(r: &InstallReport) {
    for (name, version) in &r.added {
        println!("+ {} {}", name, version);
    }
    for name in &r.removed {
        println!("- {}", name);
    }
    if r.total == 0 {
        println!("no dependencies");
    } else {
        println!(
            "{} package{}, {} reused",
            r.total,
            if r.total == 1 { "" } else { "s" },
            r.reused
        );
    }
}

fn cmd_new(args: &[String]) -> Result<u8, String> {
    let mut lib = false;
    let mut name = None;
    for a in args {
        match a.as_str() {
            "--lib" | "-l" => lib = true,
            other if other.starts_with('-') => return Err(format!("unknown flag '{}'", other)),
            other => {
                if name.is_some() {
                    return Err("cdc new takes one name".into());
                }
                name = Some(other.to_string());
            }
        }
    }
    let name = name.ok_or("usage: cdc new <name> [--lib]")?;
    if !manifest::valid_name(&name) {
        return Err(format!(
            "'{}' is not a valid package name (lowercase letters, digits, '.', '-', '_')",
            name
        ));
    }
    let dir = env::current_dir()
        .map_err(|e| e.to_string())?
        .join(&name);
    if dir.exists() {
        let empty = fs::read_dir(&dir)
            .map_err(|e| format!("{}: {}", dir.display(), e))?
            .next()
            .is_none();
        if !empty {
            return Err(format!("{} already exists", dir.display()));
        }
    }
    fs::create_dir_all(dir.join("src")).map_err(|e| format!("{}: {}", dir.display(), e))?;
    let m = Manifest {
        name: name.clone(),
        version: Version::parse("0.1.0")?,
        description: None,
        main: if lib {
            None
        } else {
            Some("src/main.rsx".to_string())
        },
        lib: if lib {
            Some("src/lib.rsx".to_string())
        } else {
            None
        },
        dependencies: BTreeMap::new(),
    };
    m.save(&dir.join(manifest::FILE))?;
    if lib {
        fs::write(dir.join("src").join("lib.rsx"), lib_template(&name))
            .map_err(|e| format!("{}: {}", dir.display(), e))?;
    } else {
        fs::write(dir.join("src").join("main.rsx"), app_template(&name))
            .map_err(|e| format!("{}: {}", dir.display(), e))?;
    }
    println!(
        "created {} ({})",
        dir.display(),
        if lib { "library" } else { "app" }
    );
    Ok(0)
}

fn cmd_init(args: &[String]) -> Result<u8, String> {
    let mut name = None;
    let mut lib = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--name" => name = Some(take(args, &mut i, "--name")?),
            "--lib" | "-l" => lib = true,
            other => return Err(format!("unexpected argument '{}'", other)),
        }
        i += 1;
    }
    let dir = env::current_dir().map_err(|e| e.to_string())?;
    if dir.join(manifest::FILE).exists() {
        return Err(format!("{} already exists", dir.join(manifest::FILE).display()));
    }
    let name = match name {
        Some(n) => n,
        None => dir
            .file_name()
            .map(|n| sanitize(&n.to_string_lossy()))
            .ok_or("cannot use this directory as a package name; pass --name")?,
    };
    if !manifest::valid_name(&name) {
        return Err(format!(
            "'{}' is not a valid package name; pass --name",
            name
        ));
    }
    let has_main = dir.join("src").join("main.rsx").is_file();
    let has_lib = dir.join("src").join("lib.rsx").is_file();
    let library = lib || (has_lib && !has_main);
    let m = Manifest {
        name: name.clone(),
        version: Version::parse("0.1.0")?,
        description: None,
        main: if library {
            None
        } else {
            Some("src/main.rsx".to_string())
        },
        lib: if library {
            Some("src/lib.rsx".to_string())
        } else {
            None
        },
        dependencies: BTreeMap::new(),
    };
    fs::create_dir_all(dir.join("src")).map_err(|e| format!("{}: {}", dir.display(), e))?;
    m.save(&dir.join(manifest::FILE))?;
    if library && !has_lib {
        fs::write(dir.join("src").join("lib.rsx"), lib_template(&name))
            .map_err(|e| format!("{}: {}", dir.display(), e))?;
    }
    if !library && !has_main {
        fs::write(dir.join("src").join("main.rsx"), app_template(&name))
            .map_err(|e| format!("{}: {}", dir.display(), e))?;
    }
    println!("created {}", dir.join(manifest::FILE).display());
    Ok(0)
}

fn cmd_install(args: &[String]) -> Result<u8, String> {
    if !args.is_empty() {
        return Err("cdc install takes no arguments".into());
    }
    let p = Project::discover()?;
    let report = p.install()?;
    print_report(&report);
    Ok(0)
}

fn cmd_add(args: &[String]) -> Result<u8, String> {
    let positional: Vec<&String> = args.iter().filter(|a| !a.starts_with('-')).collect();
    if positional.len() != 1 {
        return Err("usage: cdc add <name>[@<range>]".into());
    }
    let spec = positional[0];
    let (name, range) = split_spec(spec);
    if !manifest::valid_name(&name) {
        return Err(format!("'{}' is not a valid package name", name));
    }
    let reg = Registry::discover()?;
    let mut p = Project::discover()?;
    let range = match range {
        Some(r) => {
            Range::parse(&r)?;
            r
        }
        None => match reg.latest(&name) {
            Some((v, _)) => format!("^{}", v),
            None => return Err(format!("no package named '{}' in the registry", name)),
        },
    };
    let mut next = p.manifest.clone();
    next.dependencies.insert(name.clone(), range.clone());
    let preferred = match Lock::load(&p.dir.join("cdc.lock"))? {
        Some(l) => l.preferred(),
        None => BTreeMap::new(),
    };
    resolve(&reg, &next, &preferred)?;
    let old = p.manifest.clone();
    next.save(&p.dir.join(manifest::FILE))?;
    p.manifest = next;
    match p.install() {
        Ok(report) => {
            println!("added {} {}", name, range);
            print_report(&report);
            Ok(0)
        }
        Err(e) => {
            p.manifest = old;
            let _ = p.manifest.save(&p.dir.join(manifest::FILE));
            Err(e)
        }
    }
}

fn cmd_remove(args: &[String]) -> Result<u8, String> {
    let positional: Vec<&String> = args.iter().filter(|a| !a.starts_with('-')).collect();
    if positional.len() != 1 {
        return Err("usage: cdc remove <name>".into());
    }
    let name = positional[0];
    let mut p = Project::discover()?;
    let old = p.manifest.clone();
    if p.manifest.dependencies.remove(name).is_none() {
        return Err(format!("'{}' is not a dependency", name));
    }
    p.manifest.save(&p.dir.join(manifest::FILE))?;
    match p.install() {
        Ok(report) => {
            println!("removed {}", name);
            print_report(&report);
            Ok(0)
        }
        Err(e) => {
            p.manifest = old;
            let _ = p.manifest.save(&p.dir.join(manifest::FILE));
            Err(e)
        }
    }
}

fn cmd_build(args: &[String]) -> Result<u8, String> {
    let mut target = host_target();
    let mut out = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-t" | "--target" => {
                let value = take(args, &mut i, "-t")?;
                target = normalize_target(&value)?;
            }
            "-o" | "--out" => out = Some(PathBuf::from(take(args, &mut i, "-o")?)),
            other => return Err(format!("unexpected argument '{}'", other)),
        }
        i += 1;
    }
    let p = Project::discover()?;
    match p.build(target, out) {
        Ok(path) => {
            println!("built {}", path.display());
            Ok(0)
        }
        Err(BuildError::Message(m)) => Err(m),
        Err(BuildError::Compiler(c)) => Ok(c.clamp(1, 255) as u8),
    }
}

fn cmd_run(args: &[String]) -> Result<u8, String> {
    let mut target = host_target();
    let mut tail: Vec<OsString> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-t" | "--target" => {
                let value = take(args, &mut i, "-t")?;
                target = normalize_target(&value)?;
            }
            "--" => {
                tail = args[i + 1..].iter().map(OsString::from).collect();
                break;
            }
            other => return Err(format!("unexpected argument '{}'", other)),
        }
        i += 1;
    }
    let p = Project::discover()?;
    match p.run(target, &tail) {
        Ok(code) => Ok(code.clamp(0, 255) as u8),
        Err(BuildError::Message(m)) => Err(m),
        Err(BuildError::Compiler(c)) => Ok(c.clamp(1, 255) as u8),
    }
}

fn cmd_publish(args: &[String]) -> Result<u8, String> {
    let force = args.iter().any(|a| a == "--force" || a == "-f");
    let p = Project::discover()?;
    let reg = Registry::discover()?;
    let dest = reg.publish(&p.manifest, &p.dir, force)?;
    println!(
        "published {} {} -> {}",
        p.manifest.name,
        p.manifest.version,
        dest.display()
    );
    Ok(0)
}

fn cmd_search(args: &[String]) -> Result<u8, String> {
    let term = args.first().cloned().unwrap_or_default();
    let reg = Registry::discover()?;
    let hits = reg.search(&term);
    if hits.is_empty() {
        if term.is_empty() {
            println!("the registry is empty");
        } else {
            println!("nothing matches '{}'", term);
        }
        return Ok(0);
    }
    for h in hits {
        match h.description {
            Some(d) if !d.is_empty() => println!("{:<20} {:<10} {}", h.name, h.version, d),
            _ => println!("{:<20} {}", h.name, h.version),
        }
    }
    Ok(0)
}

fn cmd_tree(args: &[String]) -> Result<u8, String> {
    if !args.is_empty() {
        return Err("cdc tree takes no arguments".into());
    }
    let p = Project::discover()?;
    let reg = Registry::discover()?;
    let preferred = match Lock::load(&p.dir.join("cdc.lock"))? {
        Some(l) => l.preferred(),
        None => BTreeMap::new(),
    };
    let chosen = resolve(&reg, &p.manifest, &preferred)?;
    let mut out = format!("{} {}\n", p.manifest.name, p.manifest.version);
    let mut seen = BTreeSet::new();
    render_deps(&p.manifest, &reg, &chosen, "", &mut seen, &mut out)?;
    print!("{}", out);
    Ok(0)
}

fn render_deps(
    m: &Manifest,
    reg: &Registry,
    chosen: &BTreeMap<String, Version>,
    prefix: &str,
    seen: &mut BTreeSet<String>,
    out: &mut String,
) -> Result<(), String> {
    let names: Vec<&String> = m.dependencies.keys().collect();
    for (i, name) in names.iter().enumerate() {
        let last = i + 1 == names.len();
        let branch = if last { "`-- " } else { "|-- " };
        match chosen.get(*name) {
            Some(v) => {
                out.push_str(&format!("{}{}{} {}\n", prefix, branch, name, v));
                if !seen.insert((*name).clone()) {
                    continue;
                }
                let dm = reg.manifest(name, v)?;
                let child = format!("{}{}", prefix, if last { "    " } else { "|   " });
                render_deps(&dm, reg, chosen, &child, seen, out)?;
            }
            None => out.push_str(&format!("{}{}{} (unresolved)\n", prefix, branch, name)),
        }
    }
    Ok(())
}

fn split_spec(s: &str) -> (String, Option<String>) {
    match s.rfind('@') {
        Some(i) if i > 0 && i + 1 < s.len() => (s[..i].to_string(), Some(s[i + 1..].to_string())),
        Some(i) if i > 0 => (s[..i].to_string(), None),
        _ => (s.to_string(), None),
    }
}

fn sanitize(s: &str) -> String {
    let mut out = String::new();
    for c in s.to_ascii_lowercase().chars() {
        if c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_' || c == '.' {
            out.push(c);
        } else {
            out.push('-');
        }
    }
    let out = out.trim_matches('-').to_string();
    if out.is_empty() {
        "package".to_string()
    } else {
        out
    }
}

fn app_template(name: &str) -> String {
    format!(
        "extern fn printf(fmt: ptr<u8>, ...) -> i32;\n\nfn main() -> i32 {{\n    printf(\"{}\\n\");\n    return 0;\n}}\n",
        name
    )
}

fn lib_template(name: &str) -> String {
    format!(
        "fn {}_add(a: i64, b: i64) -> i64 {{\n    return a + b;\n}}\n",
        manifest::ident(name)
    )
}
