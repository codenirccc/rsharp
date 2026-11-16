use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitStatus, Stdio};

use crate::fsutil;
use crate::lock::{Entry, Lock};
use crate::manifest::{Manifest, FILE};
use crate::registry::Registry;
use crate::resolve::resolve;
use crate::semver::Version;

pub enum BuildError {
    Message(String),
    Compiler(i32),
}

impl From<String> for BuildError {
    fn from(s: String) -> BuildError {
        BuildError::Message(s)
    }
}

pub struct InstallReport {
    pub added: Vec<(String, Version)>,
    pub reused: usize,
    pub removed: Vec<String>,
    pub total: usize,
}

pub struct SourceFile {
    pub package: String,
    pub path: PathBuf,
}

pub struct Project {
    pub dir: PathBuf,
    pub manifest: Manifest,
}

impl Project {
    pub fn discover() -> Result<Project, String> {
        let mut dir = env::current_dir().map_err(|e| e.to_string())?;
        loop {
            if dir.join(FILE).is_file() {
                return Project::open(dir);
            }
            if !dir.pop() {
                break;
            }
        }
        Err("no cdc.json here or in any parent directory; run cdc new or cdc init".into())
    }

    pub fn open(dir: PathBuf) -> Result<Project, String> {
        let manifest = Manifest::load(&dir.join(FILE))?;
        Ok(Project { dir, manifest })
    }

    pub fn modules_dir(&self) -> PathBuf {
        self.dir.join("cdc_modules")
    }

    pub fn build_dir(&self) -> PathBuf {
        self.dir.join("build")
    }

    pub fn install(&self) -> Result<InstallReport, String> {
        let reg = Registry::discover()?;
        let lock_path = self.dir.join("cdc.lock");
        let old = Lock::load(&lock_path)?;
        let preferred = match &old {
            Some(l) => l.preferred(),
            None => BTreeMap::new(),
        };
        let resolved = resolve(&reg, &self.manifest, &preferred)?;
        let modules = self.modules_dir();
        fs::create_dir_all(&modules).map_err(|e| format!("{}: {}", modules.display(), e))?;

        let mut entries = Vec::new();
        let mut added = Vec::new();
        let mut reused = 0;
        for (name, version) in &resolved {
            let src = reg.package_dir(name, version);
            if !src.is_dir() {
                return Err(format!("{} {} is missing from the registry", name, version));
            }
            let hash = fsutil::hash_tree(&src)?;
            let dst = modules.join(name);
            let same = dst.is_dir() && fsutil::hash_tree(&dst).map(|h| h == hash).unwrap_or(false);
            if same {
                reused += 1;
            } else {
                fsutil::remove(&dst)?;
                fsutil::copy_tree(&src, &dst, &fsutil::SKIP)?;
                added.push((name.clone(), *version));
            }
            entries.push(Entry {
                name: name.clone(),
                version: *version,
                hash,
            });
        }

        let mut removed = Vec::new();
        if let Ok(rd) = fs::read_dir(&modules) {
            for entry in rd.flatten() {
                let name = entry.file_name().to_string_lossy().into_owned();
                if !resolved.contains_key(&name) {
                    fsutil::remove(&entry.path())?;
                    removed.push(name);
                }
            }
        }

        Lock { entries }.save(&lock_path)?;
        Ok(InstallReport {
            added,
            reused,
            removed,
            total: resolved.len(),
        })
    }

    pub fn sources(&self) -> Result<Vec<SourceFile>, String> {
        let mut out = Vec::new();
        let mut seen = BTreeSet::new();
        for name in self.manifest.dependencies.keys() {
            self.walk_dep(name, &mut seen, &mut out)?;
        }
        let main = self.manifest.main_path(&self.dir).ok_or_else(|| {
            format!(
                "{}: no entry source; add src/main.rsx or set \"main\" in cdc.json",
                self.manifest.name
            )
        })?;
        out.push(SourceFile {
            package: self.manifest.name.clone(),
            path: main,
        });
        Ok(out)
    }

    fn walk_dep(
        &self,
        name: &str,
        seen: &mut BTreeSet<String>,
        out: &mut Vec<SourceFile>,
    ) -> Result<(), String> {
        if !seen.insert(name.to_string()) {
            return Ok(());
        }
        let dir = self.modules_dir().join(name);
        let manifest_path = dir.join(FILE);
        if !manifest_path.is_file() {
            return Err(format!("package '{}' is not installed; run cdc install", name));
        }
        let m = Manifest::load(&manifest_path)?;
        for dep in m.dependencies.keys() {
            self.walk_dep(dep, seen, out)?;
        }
        let path = m
            .lib_path(&dir)
            .ok_or_else(|| format!("package '{}' has no source file", name))?;
        out.push(SourceFile {
            package: name.to_string(),
            path,
        });
        Ok(())
    }

    pub fn build(&self, target: &str, out: Option<PathBuf>) -> Result<PathBuf, BuildError> {
        let report = self.install()?;
        for (name, version) in &report.added {
            eprintln!("+ {} {}", name, version);
        }

        let files = self.sources()?;
        scan(&files)?;

        let mut merged = String::new();
        for f in &files {
            let text =
                fs::read_to_string(&f.path).map_err(|e| format!("{}: {}", f.path.display(), e))?;
            merged.push_str(&text);
            if !text.ends_with('\n') {
                merged.push('\n');
            }
            merged.push('\n');
        }

        let bdir = self.build_dir();
        fs::create_dir_all(&bdir).map_err(|e| format!("{}: {}", bdir.display(), e))?;
        let merged_path = bdir.join(format!("{}.rsx", self.manifest.name));
        fs::write(&merged_path, merged).map_err(|e| format!("{}: {}", merged_path.display(), e))?;

        let exe = match out {
            Some(p) => p,
            None => bdir.join(format!(
                "{}{}",
                self.manifest.name,
                if target == "macos" { "" } else { ".exe" }
            )),
        };
        let rsc = find_rsc()?;
        let mut cmd = Command::new(&rsc.program);
        cmd.args(&rsc.prefix)
            .arg("-t")
            .arg(target)
            .arg(&merged_path)
            .arg(&exe)
            .stdin(Stdio::inherit())
            .stdout(Stdio::null())
            .stderr(Stdio::inherit());
        let status = cmd
            .status()
            .map_err(|e| format!("cannot run {}: {}", rsc.program, e))?;
        if !status.success() {
            return Err(BuildError::Compiler(exit_code(status)));
        }
        Ok(exe)
    }

    pub fn run(&self, target: &str, args: &[OsString]) -> Result<i32, BuildError> {
        let exe = self.build(target, None)?;
        eprintln!("running {}", exe.display());
        let status = Command::new(&exe).args(args).status().map_err(|e| {
            BuildError::Message(format!("cannot run {}: {}", exe.display(), e))
        })?;
        Ok(exit_code(status))
    }
}

fn exit_code(status: ExitStatus) -> i32 {
    status.code().unwrap_or(1)
}

struct Rsc {
    program: String,
    prefix: Vec<String>,
}

impl Rsc {
    fn at(path: PathBuf) -> Rsc {
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_ascii_lowercase();
        let text = path.to_string_lossy().into_owned();
        if cfg!(windows) && (ext == "cmd" || ext == "bat") {
            Rsc {
                program: "cmd".into(),
                prefix: vec!["/c".into(), text],
            }
        } else {
            Rsc {
                program: text,
                prefix: Vec::new(),
            }
        }
    }
}

fn find_rsc() -> Result<Rsc, String> {
    if let Some(p) = env::var_os("CDC_RSC") {
        return Ok(Rsc::at(PathBuf::from(p)));
    }
    let mut starts = Vec::new();
    if let Ok(exe) = env::current_exe() {
        if let Some(d) = exe.parent() {
            starts.push(d.to_path_buf());
        }
    }
    if let Ok(cwd) = env::current_dir() {
        starts.push(cwd);
    }
    for start in starts {
        let mut dir = Some(start);
        for _ in 0..8 {
            let Some(d) = dir else { break };
            for name in ["rsc.cmd", "rsc.sh"] {
                let p = d.join(name);
                if p.is_file() {
                    return Ok(Rsc::at(p));
                }
            }
            dir = d.parent().map(|p| p.to_path_buf());
        }
    }
    Err("rsc not found; put rsc.cmd on PATH or set CDC_RSC to its full path".into())
}

struct Site {
    file: String,
    line: usize,
    external: bool,
    package: String,
}

fn scan(files: &[SourceFile]) -> Result<(), String> {
    let mut seen: BTreeMap<String, Site> = BTreeMap::new();
    for f in files {
        let text =
            fs::read_to_string(&f.path).map_err(|e| format!("{}: {}", f.path.display(), e))?;
        for (i, raw) in text.lines().enumerate() {
            let Some((name, external)) = declaration(raw) else {
                continue;
            };
            let here = format!("{}:{} ({})", f.path.display(), i + 1, f.package);
            match seen.get(&name) {
                None => {
                    seen.insert(
                        name,
                        Site {
                            file: f.path.display().to_string(),
                            line: i + 1,
                            external,
                            package: f.package.clone(),
                        },
                    );
                }
                Some(prev) => {
                    if prev.external && external {
                        continue;
                    }
                    let there = format!("{}:{} ({})", prev.file, prev.line, prev.package);
                    if prev.external != external {
                        let (decl, def) = if prev.external {
                            (there, here)
                        } else {
                            (here, there)
                        };
                        return Err(format!(
                            "'{}' is declared extern at {} and defined at {}",
                            name, decl, def
                        ));
                    }
                    return Err(format!("'{}' is defined twice: {} and {}", name, there, here));
                }
            }
        }
    }
    Ok(())
}

fn declaration(line: &str) -> Option<(String, bool)> {
    let t = line.trim_start();
    let (rest, external) = match t.strip_prefix("extern ") {
        Some(r) => (r.trim_start(), true),
        None => (t, false),
    };
    let rest = rest
        .strip_prefix("fn ")
        .or_else(|| rest.strip_prefix("struct "))
        .or_else(|| rest.strip_prefix("const "))?;
    let name: String = rest
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if name.is_empty() {
        None
    } else {
        Some((name, external))
    }
}
