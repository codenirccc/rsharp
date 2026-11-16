use std::fmt;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Version {
    pub major: u64,
    pub minor: u64,
    pub patch: u64,
}

impl Version {
    pub fn new(major: u64, minor: u64, patch: u64) -> Version {
        Version { major, minor, patch }
    }

    pub fn parse(s: &str) -> Result<Version, String> {
        let (v, given) = parse_parts(s)?;
        if given != 3 {
            return Err(format!("'{}' is not a full version (want major.minor.patch)", s));
        }
        Ok(v)
    }
}

impl fmt::Display for Version {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

fn parse_parts(s: &str) -> Result<(Version, usize), String> {
    let s = s.trim();
    if s.is_empty() {
        return Err("empty version".into());
    }
    if s.contains('-') || s.contains('+') {
        return Err(format!("'{}': pre-release and build tags are not supported", s));
    }
    let mut nums = [0u64; 3];
    let mut given = 0;
    for part in s.split('.') {
        if given == 3 {
            return Err(format!("'{}' has too many parts", s));
        }
        if part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()) {
            return Err(format!("'{}' has a non-numeric part", s));
        }
        nums[given] = part
            .parse::<u64>()
            .map_err(|_| format!("'{}': number out of range", s))?;
        given += 1;
    }
    Ok((Version::new(nums[0], nums[1], nums[2]), given))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Op {
    Eq,
    Gt,
    Ge,
    Lt,
    Le,
}

#[derive(Clone, Copy, Debug)]
struct Comparator {
    op: Op,
    ver: Version,
}

impl Comparator {
    fn matches(&self, v: &Version) -> bool {
        match self.op {
            Op::Eq => v == &self.ver,
            Op::Gt => v > &self.ver,
            Op::Ge => v >= &self.ver,
            Op::Lt => v < &self.ver,
            Op::Le => v <= &self.ver,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Range {
    text: String,
    comps: Vec<Comparator>,
}

impl Range {
    pub fn parse(s: &str) -> Result<Range, String> {
        let text = s.trim().to_string();
        if text.is_empty() || text == "*" {
            return Ok(Range { text, comps: Vec::new() });
        }
        let mut comps = Vec::new();
        let words: Vec<String> = text
            .split_whitespace()
            .map(|w| w.trim_matches(',').to_string())
            .filter(|w| !w.is_empty())
            .collect();
        let mut tokens: Vec<String> = Vec::new();
        let mut i = 0;
        while i < words.len() {
            let w = &words[i];
            if matches!(w.as_str(), ">=" | "<=" | ">" | "<" | "=" | "^" | "~")
                && i + 1 < words.len()
            {
                tokens.push(format!("{}{}", w, words[i + 1]));
                i += 2;
            } else {
                tokens.push(w.clone());
                i += 1;
            }
        }
        for token in tokens.iter().map(|s| s.as_str()) {
            if token == "*" {
                continue;
            }
            if let Some(rest) = token.strip_prefix('^') {
                let (v, given) = parse_parts(rest)?;
                comps.push(Comparator { op: Op::Ge, ver: v });
                comps.push(Comparator { op: Op::Lt, ver: caret_upper(v, given) });
            } else if let Some(rest) = token.strip_prefix('~') {
                let (v, given) = parse_parts(rest)?;
                comps.push(Comparator { op: Op::Ge, ver: v });
                comps.push(Comparator { op: Op::Lt, ver: tilde_upper(v, given) });
            } else if let Some(rest) = token.strip_prefix(">=") {
                comps.push(Comparator { op: Op::Ge, ver: bounds(rest)? });
            } else if let Some(rest) = token.strip_prefix("<=") {
                comps.push(Comparator { op: Op::Le, ver: bounds(rest)? });
            } else if let Some(rest) = token.strip_prefix('>') {
                comps.push(Comparator { op: Op::Gt, ver: bounds(rest)? });
            } else if let Some(rest) = token.strip_prefix('<') {
                comps.push(Comparator { op: Op::Lt, ver: bounds(rest)? });
            } else if let Some(rest) = token.strip_prefix('=') {
                let (v, given) = parse_parts(rest)?;
                push_eq(&mut comps, v, given);
            } else {
                let (v, given) = parse_parts(token)?;
                push_eq(&mut comps, v, given);
            }
        }
        Ok(Range { text, comps })
    }

    pub fn matches(&self, v: &Version) -> bool {
        self.comps.iter().all(|c| c.matches(v))
    }

    pub fn as_str(&self) -> &str {
        &self.text
    }
}

fn bounds(s: &str) -> Result<Version, String> {
    let (v, given) = parse_parts(s)?;
    if given != 3 {
        return Err(format!("'{}' is not a full version", s.trim()));
    }
    Ok(v)
}

fn push_eq(comps: &mut Vec<Comparator>, v: Version, given: usize) {
    match given {
        1 => {
            comps.push(Comparator { op: Op::Ge, ver: v });
            comps.push(Comparator {
                op: Op::Lt,
                ver: Version::new(v.major.saturating_add(1), 0, 0),
            });
        }
        2 => {
            comps.push(Comparator { op: Op::Ge, ver: v });
            comps.push(Comparator {
                op: Op::Lt,
                ver: Version::new(v.major, v.minor.saturating_add(1), 0),
            });
        }
        _ => comps.push(Comparator { op: Op::Eq, ver: v }),
    }
}

fn caret_upper(v: Version, given: usize) -> Version {
    if v.major > 0 {
        Version::new(v.major.saturating_add(1), 0, 0)
    } else if given == 1 {
        Version::new(1, 0, 0)
    } else if v.minor > 0 {
        Version::new(0, v.minor.saturating_add(1), 0)
    } else if given == 2 {
        Version::new(0, 1, 0)
    } else {
        Version::new(0, 0, v.patch.saturating_add(1))
    }
}

fn tilde_upper(v: Version, given: usize) -> Version {
    if given == 1 {
        Version::new(v.major.saturating_add(1), 0, 0)
    } else {
        Version::new(v.major, v.minor.saturating_add(1), 0)
    }
}
