use std::collections::BTreeMap;

use crate::manifest::Manifest;
use crate::registry::Registry;
use crate::semver::{Range, Version};

#[derive(Clone)]
struct Req {
    range: Range,
    from: String,
}

pub fn resolve(
    reg: &Registry,
    root: &Manifest,
    preferred: &BTreeMap<String, Version>,
) -> Result<BTreeMap<String, Version>, String> {
    let mut reqs: BTreeMap<String, Vec<Req>> = BTreeMap::new();
    for (name, range) in &root.dependencies {
        let parsed = Range::parse(range).map_err(|e| format!("'{}': {}", name, e))?;
        reqs.entry(name.clone()).or_default().push(Req {
            range: parsed,
            from: root.name.clone(),
        });
    }
    let chosen = BTreeMap::new();
    let mut steps = 200_000u32;
    let mut diag = None;
    match solve(reg, &chosen, &reqs, preferred, &mut steps, &mut diag) {
        Ok(map) => Ok(map),
        Err(e) => Err(diag.unwrap_or(e)),
    }
}

fn solve(
    reg: &Registry,
    chosen: &BTreeMap<String, Version>,
    reqs: &BTreeMap<String, Vec<Req>>,
    preferred: &BTreeMap<String, Version>,
    steps: &mut u32,
    diag: &mut Option<String>,
) -> Result<BTreeMap<String, Version>, String> {
    if *steps == 0 {
        return Err("dependency resolution ran out of steps".into());
    }
    *steps -= 1;

    let next = reqs
        .iter()
        .find(|(name, _)| !chosen.contains_key(*name))
        .map(|(name, list)| (name.clone(), list.clone()));
    let (name, list) = match next {
        Some(x) => x,
        None => return Ok(chosen.clone()),
    };

    let available = reg.versions(&name);
    let mut candidates: Vec<Version> = available
        .iter()
        .copied()
        .filter(|v| list.iter().all(|r| r.range.matches(v)))
        .collect();
    candidates.sort();
    candidates.reverse();
    if let Some(p) = preferred.get(&name) {
        if let Some(pos) = candidates.iter().position(|v| v == p) {
            let v = candidates.remove(pos);
            candidates.insert(0, v);
        }
    }

    if candidates.is_empty() {
        let msg = if available.is_empty() {
            format!("no package named '{}' in the registry", name)
        } else {
            let wants = list
                .iter()
                .map(|r| format!("{} (from {})", r.range.as_str(), r.from))
                .collect::<Vec<_>>()
                .join(" and ");
            let have = available
                .iter()
                .map(|v| v.to_string())
                .collect::<Vec<_>>()
                .join(", ");
            format!(
                "no version of '{}' satisfies {}; the registry has {}",
                name, wants, have
            )
        };
        if list.len() > 1 && diag.is_none() {
            *diag = Some(msg.clone());
        }
        return Err(msg);
    }

    for version in candidates {
        let m = reg.manifest(&name, &version)?;
        let mut next_chosen = chosen.clone();
        next_chosen.insert(name.clone(), version);
        let mut next_reqs = reqs.clone();
        let mut fits = true;
        for (dep, range) in &m.dependencies {
            let parsed = Range::parse(range).map_err(|e| format!("'{}': {}", dep, e))?;
            if let Some(v) = next_chosen.get(dep) {
                if !parsed.matches(v) {
                    if diag.is_none() {
                        *diag = Some(format!(
                            "{} {} is already selected, but {} {} needs {} {}",
                            dep, v, name, version, dep, range
                        ));
                    }
                    fits = false;
                    break;
                }
            }
            next_reqs.entry(dep.clone()).or_default().push(Req {
                range: parsed,
                from: format!("{} {}", name, version),
            });
        }
        if !fits {
            continue;
        }
        if let Ok(done) = solve(reg, &next_chosen, &next_reqs, preferred, steps, diag) {
            return Ok(done);
        }
    }

    Err(format!(
        "no combination of versions satisfies '{}'",
        name
    ))
}
