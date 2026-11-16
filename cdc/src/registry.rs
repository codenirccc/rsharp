use std::fs;
use std::path::{Path, PathBuf};

use crate::fsutil;
use crate::manifest::{Manifest, FILE};
use crate::semver::Version;

pub struct Registry {
    root: PathBuf,
}

#[derive(Clone, Debug)]
pub struct PackageInfo {
    pub name: String,
    pub version: Version,
    pub description: Option<String>,
}

impl Registry {
    pub fn discover() -> Result<Registry, String> {
        if let Some(p) = std::env::var_os("CDC_REGISTRY") {
            let root = PathBuf::from(p);
            fs::create_dir_all(&root).map_err(|e| format!("{}: {}", root.display(), e))?;
            return Ok(Registry { root });
        }
        let home = std::env::var_os("USERPROFILE")
            .or_else(|| std::env::var_os("HOME"))
            .ok_or("no home directory; set CDC_REGISTRY to a directory")?;
        let root = PathBuf::from(home).join(".cdc-registry");
        fs::create_dir_all(&root).map_err(|e| format!("{}: {}", root.display(), e))?;
        Ok(Registry { root })
    }

    pub fn package_dir(&self, name: &str, version: &Version) -> PathBuf {
        self.root.join(name).join(version.to_string())
    }

    pub fn versions(&self, name: &str) -> Vec<Version> {
        let dir = self.root.join(name);
        let mut out = Vec::new();
        if let Ok(rd) = fs::read_dir(&dir) {
            for entry in rd.flatten() {
                if !entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                    continue;
                }
                let name = entry.file_name();
                let name = name.to_string_lossy();
                if let Ok(v) = Version::parse(&name) {
                    out.push(v);
                }
            }
        }
        out.sort();
        out
    }

    pub fn manifest(&self, name: &str, version: &Version) -> Result<Manifest, String> {
        let path = self.package_dir(name, version).join(FILE);
        Manifest::load(&path)
    }

    pub fn latest(&self, name: &str) -> Option<(Version, Manifest)> {
        for v in self.versions(name).iter().rev() {
            if let Ok(m) = self.manifest(name, v) {
                return Some((*v, m));
            }
        }
        None
    }

    pub fn list(&self) -> Vec<PackageInfo> {
        let mut out = Vec::new();
        let rd = match fs::read_dir(&self.root) {
            Ok(rd) => rd,
            Err(_) => return out,
        };
        for entry in rd.flatten() {
            if !entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if let Some((version, m)) = self.latest(&name) {
                out.push(PackageInfo {
                    name,
                    version,
                    description: m.description,
                });
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        out
    }

    pub fn search(&self, term: &str) -> Vec<PackageInfo> {
        let term = term.to_lowercase();
        self.list()
            .into_iter()
            .filter(|p| {
                term.is_empty()
                    || p.name.to_lowercase().contains(&term)
                    || p.description
                        .as_deref()
                        .map(|d| d.to_lowercase().contains(&term))
                        .unwrap_or(false)
            })
            .collect()
    }

    pub fn publish(&self, m: &Manifest, project: &Path, force: bool) -> Result<PathBuf, String> {
        if m.main_path(project).is_none() && m.lib_path(project).is_none() {
            return Err(format!(
                "{}: no source file; expected src/main.rsx, src/lib.rsx, or a \"main\"/\"lib\" entry",
                project.display()
            ));
        }
        let dest = self.package_dir(&m.name, &m.version);
        if dest.exists() {
            if !force {
                return Err(format!(
                    "{} {} is already published; pass --force to replace it",
                    m.name, m.version
                ));
            }
            fsutil::remove(&dest)?;
        }
        fsutil::copy_tree(project, &dest, &fsutil::SKIP)?;
        m.save(&dest.join(FILE))?;
        Ok(dest)
    }
}
