use std::fs;
use std::path::{Path, PathBuf};

use crate::sha256;

pub const SKIP: [&str; 4] = ["cdc_modules", "build", "target", ".git"];

pub fn copy_tree(src: &Path, dst: &Path, skip: &[&str]) -> Result<(), String> {
    fs::create_dir_all(dst).map_err(|e| format!("{}: {}", dst.display(), e))?;
    let rd = fs::read_dir(src).map_err(|e| format!("{}: {}", src.display(), e))?;
    for entry in rd {
        let entry = entry.map_err(|e| format!("{}: {}", src.display(), e))?;
        let name = entry.file_name();
        if skip.iter().any(|s| **s == name.to_string_lossy()) {
            continue;
        }
        let from = entry.path();
        let to = dst.join(&name);
        let ty = entry
            .file_type()
            .map_err(|e| format!("{}: {}", from.display(), e))?;
        if ty.is_dir() {
            copy_tree(&from, &to, skip)?;
        } else if ty.is_file() {
            fs::copy(&from, &to)
                .map_err(|e| format!("{} -> {}: {}", from.display(), to.display(), e))?;
        }
    }
    Ok(())
}

pub fn hash_tree(dir: &Path) -> Result<String, String> {
    let mut files = Vec::new();
    collect(dir, dir, &mut files)?;
    files.sort_by(|a, b| a.0.cmp(&b.0));
    let mut h = sha256::Sha256::new();
    for (rel, path) in files {
        let data = fs::read(&path).map_err(|e| format!("{}: {}", path.display(), e))?;
        h.update(rel.as_bytes());
        h.update(&[0]);
        h.update(&(data.len() as u64).to_le_bytes());
        h.update(&data);
    }
    Ok(sha256::hex(&h.finish()))
}

fn collect(root: &Path, dir: &Path, out: &mut Vec<(String, PathBuf)>) -> Result<(), String> {
    let rd = fs::read_dir(dir).map_err(|e| format!("{}: {}", dir.display(), e))?;
    for entry in rd {
        let entry = entry.map_err(|e| format!("{}: {}", dir.display(), e))?;
        let name = entry.file_name();
        if SKIP.iter().any(|s| *s == name.to_string_lossy()) {
            continue;
        }
        let path = entry.path();
        let ty = entry
            .file_type()
            .map_err(|e| format!("{}: {}", path.display(), e))?;
        if ty.is_dir() {
            collect(root, &path, out)?;
        } else if ty.is_file() {
            let rel = path
                .strip_prefix(root)
                .map_err(|e| format!("{}: {}", path.display(), e))?;
            let rel = rel
                .components()
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join("/");
            out.push((rel, path));
        }
    }
    Ok(())
}

pub fn remove(path: &Path) -> Result<(), String> {
    if !path.exists() {
        return Ok(());
    }
    let meta = fs::symlink_metadata(path).map_err(|e| format!("{}: {}", path.display(), e))?;
    if meta.is_dir() {
        fs::remove_dir_all(path).map_err(|e| format!("{}: {}", path.display(), e))
    } else {
        fs::remove_file(path).map_err(|e| format!("{}: {}", path.display(), e))
    }
}
