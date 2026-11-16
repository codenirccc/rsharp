use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use crate::json::Value;
use crate::semver::Version;

const VERSION: i64 = 1;

#[derive(Clone, Debug)]
pub struct Entry {
    pub name: String,
    pub version: Version,
    pub hash: String,
}

#[derive(Clone, Debug)]
pub struct Lock {
    pub entries: Vec<Entry>,
}

impl Lock {
    pub fn load(path: &Path) -> Result<Option<Lock>, String> {
        if !path.exists() {
            return Ok(None);
        }
        let text = fs::read_to_string(path).map_err(|e| format!("{}: {}", path.display(), e))?;
        let v = Value::parse(&text).map_err(|e| format!("{}: {}", path.display(), e))?;
        match v.get("lock_version").and_then(|x| x.as_i64()) {
            Some(VERSION) => {}
            Some(n) => return Err(format!("{}: lock version {} is not supported", path.display(), n)),
            None => return Err(format!("{}: missing \"lock_version\"", path.display())),
        }
        let mut entries = Vec::new();
        let packages = match v.get("packages") {
            Some(Value::Array(a)) => a.clone(),
            _ => return Err(format!("{}: missing \"packages\"", path.display())),
        };
        for p in packages {
            let name = p
                .get("name")
                .and_then(|x| x.as_str())
                .ok_or_else(|| format!("{}: package without a name", path.display()))?
                .to_string();
            let version = p
                .get("version")
                .and_then(|x| x.as_str())
                .ok_or_else(|| format!("{}: {} has no version", path.display(), name))?;
            let version = Version::parse(version)?;
            let hash = p
                .get("hash")
                .and_then(|x| x.as_str())
                .ok_or_else(|| format!("{}: {} has no hash", path.display(), name))?
                .to_string();
            entries.push(Entry { name, version, hash });
        }
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(Some(Lock { entries }))
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        let mut entries = self.entries.clone();
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        let packages = entries
            .iter()
            .map(|e| {
                Value::Object(vec![
                    ("name".to_string(), Value::Str(e.name.clone())),
                    ("version".to_string(), Value::Str(e.version.to_string())),
                    ("hash".to_string(), Value::Str(e.hash.clone())),
                ])
            })
            .collect();
        let v = Value::Object(vec![
            ("lock_version".to_string(), Value::Int(VERSION)),
            ("packages".to_string(), Value::Array(packages)),
        ]);
        fs::write(path, format!("{}\n", v.to_pretty()))
            .map_err(|e| format!("{}: {}", path.display(), e))
    }

    pub fn preferred(&self) -> BTreeMap<String, Version> {
        self.entries
            .iter()
            .map(|e| (e.name.clone(), e.version))
            .collect()
    }
}
