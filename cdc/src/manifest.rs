use std::collections::BTreeMap;
use std::fs;
use std::path::{Component, Path, PathBuf};

use crate::json::Value;
use crate::semver::{Range, Version};

pub const FILE: &str = "cdc.json";

#[derive(Clone, Debug)]
pub struct Manifest {
    pub name: String,
    pub version: Version,
    pub description: Option<String>,
    pub main: Option<String>,
    pub lib: Option<String>,
    pub dependencies: BTreeMap<String, String>,
}

impl Manifest {
    pub fn parse(text: &str) -> Result<Manifest, String> {
        let v = Value::parse(text)?;
        Manifest::from_value(&v)
    }

    pub fn from_value(v: &Value) -> Result<Manifest, String> {
        if v.as_object().is_none() {
            return Err("manifest must be a JSON object".into());
        }
        let name = match v.get("name").and_then(|x| x.as_str()) {
            Some(s) => s.to_string(),
            None => return Err("missing \"name\"".into()),
        };
        if !valid_name(&name) {
            return Err(format!(
                "\"{}\" is not a valid package name (lowercase letters, digits, '.', '-', '_')",
                name
            ));
        }
        let version = match v.get("version").and_then(|x| x.as_str()) {
            Some(s) => Version::parse(s)?,
            None => return Err("missing \"version\"".into()),
        };
        let description = match v.get("description") {
            Some(Value::Str(s)) => Some(s.clone()),
            Some(Value::Null) | None => None,
            Some(_) => return Err("\"description\" must be a string".into()),
        };
        let main = optional_path(v, "main")?;
        let lib = optional_path(v, "lib")?;
        let mut dependencies = BTreeMap::new();
        match v.get("dependencies") {
            Some(Value::Object(kv)) => {
                for (k, val) in kv {
                    if !valid_name(k) {
                        return Err(format!("\"{}\" is not a valid dependency name", k));
                    }
                    let s = match val.as_str() {
                        Some(s) => s,
                        None => return Err(format!("dependency '{}' must be a range string", k)),
                    };
                    Range::parse(s).map_err(|e| format!("dependency '{}': {}", k, e))?;
                    dependencies.insert(k.clone(), s.to_string());
                }
            }
            Some(Value::Null) | None => {}
            Some(_) => return Err("\"dependencies\" must be an object".into()),
        }
        Ok(Manifest {
            name,
            version,
            description,
            main,
            lib,
            dependencies,
        })
    }

    pub fn load(path: &Path) -> Result<Manifest, String> {
        let text = fs::read_to_string(path).map_err(|e| format!("{}: {}", path.display(), e))?;
        Manifest::parse(&text).map_err(|e| format!("{}: {}", path.display(), e))
    }

    pub fn to_value(&self) -> Value {
        let mut kv = vec![
            ("name".to_string(), Value::Str(self.name.clone())),
            ("version".to_string(), Value::Str(self.version.to_string())),
        ];
        if let Some(d) = &self.description {
            if !d.is_empty() {
                kv.push(("description".to_string(), Value::Str(d.clone())));
            }
        }
        if let Some(m) = &self.main {
            kv.push(("main".to_string(), Value::Str(m.clone())));
        }
        if let Some(l) = &self.lib {
            kv.push(("lib".to_string(), Value::Str(l.clone())));
        }
        let deps = self
            .dependencies
            .iter()
            .map(|(k, v)| (k.clone(), Value::Str(v.clone())))
            .collect();
        kv.push(("dependencies".to_string(), Value::Object(deps)));
        Value::Object(kv)
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        let text = format!("{}\n", self.to_value().to_pretty());
        fs::write(path, text).map_err(|e| format!("{}: {}", path.display(), e))
    }

    pub fn main_path(&self, dir: &Path) -> Option<PathBuf> {
        if let Some(m) = &self.main {
            return Some(dir.join(m));
        }
        let p = dir.join("src").join("main.rsx");
        if p.is_file() {
            Some(p)
        } else {
            None
        }
    }

    pub fn lib_path(&self, dir: &Path) -> Option<PathBuf> {
        if let Some(l) = &self.lib {
            return Some(dir.join(l));
        }
        if let Some(m) = &self.main {
            return Some(dir.join(m));
        }
        let lib = dir.join("src").join("lib.rsx");
        if lib.is_file() {
            return Some(lib);
        }
        let main = dir.join("src").join("main.rsx");
        if main.is_file() {
            Some(main)
        } else {
            None
        }
    }
}

fn optional_path(v: &Value, key: &str) -> Result<Option<String>, String> {
    match v.get(key) {
        Some(Value::Str(s)) => {
            check_rel(s)?;
            Ok(Some(s.clone()))
        }
        Some(Value::Null) | None => Ok(None),
        Some(_) => Err(format!("\"{}\" must be a string", key)),
    }
}

fn check_rel(s: &str) -> Result<(), String> {
    if s.is_empty() {
        return Err("a source path cannot be empty".into());
    }
    for c in Path::new(s).components() {
        match c {
            Component::Normal(_) | Component::CurDir => {}
            _ => return Err(format!("'{}' must be a relative path inside the package", s)),
        }
    }
    Ok(())
}

pub fn valid_name(name: &str) -> bool {
    let mut chars = name.chars();
    match chars.next() {
        Some(c) if c.is_ascii_lowercase() || c.is_ascii_digit() => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_' || c == '.')
}

pub fn ident(name: &str) -> String {
    let mut out = String::new();
    for c in name.chars() {
        if c.is_ascii_alphanumeric() || c == '_' {
            out.push(c);
        } else {
            out.push('_');
        }
    }
    if out.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(true) {
        out.insert_str(0, "pkg_");
    }
    out
}
