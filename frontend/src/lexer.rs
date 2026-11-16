#[derive(Clone, Debug, PartialEq)]
pub enum Tok {
    Ident(String),
    Int(i64),
    Float(f64),
    Str(String),
    Sym(&'static str),
    Eof,
}

#[derive(Clone, Debug)]
pub struct Token {
    pub tok: Tok,
    pub line: u32,
    pub col: u32,
    pub start: usize,
    pub end: usize,
}

fn sym_at(src: &[u8], pos: usize) -> Option<(&'static str, usize)> {
    let rest = src.get(pos..)?;
    let c = *rest.first()?;
    match c {
        b'.' => {
            if rest.starts_with(b"...") {
                Some(("...", 3))
            } else if rest.starts_with(b"..=") {
                Some(("..=", 3))
            } else if rest.len() >= 2 && rest[1] == b'.' {
                Some(("..", 2))
            } else {
                Some((".", 1))
            }
        }
        b':' => {
            if rest.starts_with(b"::") {
                Some(("::", 2))
            } else {
                Some((":", 1))
            }
        }
        b'-' => {
            if rest.starts_with(b"->") {
                Some(("->", 2))
            } else if rest.starts_with(b"-=") {
                Some(("-=", 2))
            } else {
                Some(("-", 1))
            }
        }
        b'=' => {
            if rest.starts_with(b"=>") {
                Some(("=>", 2))
            } else if rest.starts_with(b"==") {
                Some(("==", 2))
            } else {
                Some(("=", 1))
            }
        }
        b'!' => {
            if rest.starts_with(b"!=") {
                Some(("!=", 2))
            } else {
                Some(("!", 1))
            }
        }
        b'<' => {
            if rest.starts_with(b"<<=") {
                Some(("<<=", 3))
            } else if rest.starts_with(b"<=") {
                Some(("<=", 2))
            } else if rest.starts_with(b"<<") {
                Some(("<<", 2))
            } else {
                Some(("<", 1))
            }
        }
        b'>' => {
            if rest.starts_with(b">>=") {
                Some((">>=", 3))
            } else if rest.starts_with(b">=") {
                Some((">=", 2))
            } else {
                Some((">", 1))
            }
        }
        b'&' => {
            if rest.starts_with(b"&&") {
                Some(("&&", 2))
            } else if rest.starts_with(b"&=") {
                Some(("&=", 2))
            } else {
                Some(("&", 1))
            }
        }
        b'|' => {
            if rest.starts_with(b"||") {
                Some(("||", 2))
            } else if rest.starts_with(b"|=") {
                Some(("|=", 2))
            } else {
                Some(("|", 1))
            }
        }
        b'^' => {
            if rest.starts_with(b"^=") {
                Some(("^=", 2))
            } else {
                Some(("^", 1))
            }
        }
        b'+' => {
            if rest.starts_with(b"+=") {
                Some(("+=", 2))
            } else {
                Some(("+", 1))
            }
        }
        b'*' => {
            if rest.starts_with(b"*=") {
                Some(("*=", 2))
            } else {
                Some(("*", 1))
            }
        }
        b'/' => {
            if rest.starts_with(b"/=") {
                Some(("/=", 2))
            } else {
                Some(("/", 1))
            }
        }
        b'%' => {
            if rest.starts_with(b"%=") {
                Some(("%=", 2))
            } else {
                Some(("%", 1))
            }
        }
        b';' => Some((";", 1)),
        b',' => Some((",", 1)),
        b'(' => Some(("(", 1)),
        b')' => Some((")", 1)),
        b'{' => Some(("{", 1)),
        b'}' => Some(("}", 1)),
        b'[' => Some(("[", 1)),
        b']' => Some(("]", 1)),
        b'~' => Some(("~", 1)),
        b'\'' => Some(("'", 1)),
        _ => None,
    }
}

fn dec_i64(digits: &[u8]) -> Option<i64> {
    let mut v: i64 = 0;
    for &d in digits {
        if d == b'_' {
            continue;
        }
        if !d.is_ascii_digit() {
            return None;
        }
        v = v.checked_mul(10)?.checked_add((d - b'0') as i64)?;
    }
    Some(v)
}

fn hex_i64(digits: &[u8]) -> Option<i64> {
    let mut v: i64 = 0;
    for &d in digits {
        if d == b'_' {
            continue;
        }
        let nib = match d {
            b'0'..=b'9' => d - b'0',
            b'a'..=b'f' => d - b'a' + 10,
            b'A'..=b'F' => d - b'A' + 10,
            _ => return None,
        };
        v = v.checked_mul(16)?.checked_add(nib as i64)?;
    }
    Some(v)
}

pub fn tokenize(src: &str) -> Result<Vec<Token>, String> {
    let b = src.as_bytes();
    let mut i = 0usize;
    let mut line = 1u32;
    let mut col = 1u32;
    let mut out: Vec<Token> = Vec::with_capacity(b.len() / 5 + 16);

    while i < b.len() {
        let c = b[i];

        if c == b'\n' {
            i += 1;
            line += 1;
            col = 1;
            continue;
        }
        if c == b' ' || c == b'\t' || c == b'\r' {
            i += 1;
            col += 1;
            continue;
        }

        if c == b'/' && i + 1 < b.len() && b[i + 1] == b'/' {
            while i < b.len() && b[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        if c == b'/' && i + 1 < b.len() && b[i + 1] == b'*' {
            i += 2;
            col += 2;
            loop {
                if i + 1 >= b.len() {
                    return Err(format!("line {}: unterminated block comment", line));
                }
                if b[i] == b'*' && b[i + 1] == b'/' {
                    i += 2;
                    col += 2;
                    break;
                }
                if b[i] == b'\n' {
                    line += 1;
                    col = 1;
                    i += 1;
                } else {
                    i += 1;
                    col += 1;
                }
            }
            continue;
        }

        let start = i;
        let sline = line;
        let scol = col;

        if c.is_ascii_alphabetic() || c == b'_' {
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
                i += 1;
                col += 1;
            }
            let text = String::from_utf8_lossy(&b[start..i]).into_owned();
            out.push(Token { tok: Tok::Ident(text), line: sline, col: scol, start, end: i });
            continue;
        }

        if c.is_ascii_digit() {
            if c == b'0' && i + 1 < b.len() && (b[i + 1] == b'x' || b[i + 1] == b'X') {
                i += 2;
                col += 2;
                let hs = i;
                while i < b.len() && (b[i].is_ascii_hexdigit() || b[i] == b'_') {
                    i += 1;
                    col += 1;
                }
                if i == hs {
                    return Err(format!("line {}: empty hex literal", sline));
                }
                let v = hex_i64(&b[hs..i])
                    .ok_or_else(|| format!("line {}: hex literal does not fit in 64 bits", sline))?;
                out.push(Token { tok: Tok::Int(v), line: sline, col: scol, start, end: i });
                continue;
            }

            let mut is_float = false;
            while i < b.len() && (b[i].is_ascii_digit() || b[i] == b'_') {
                i += 1;
                col += 1;
            }
            if i + 1 < b.len() && b[i] == b'.' && b[i + 1].is_ascii_digit() {
                is_float = true;
                i += 1;
                col += 1;
                while i < b.len() && (b[i].is_ascii_digit() || b[i] == b'_') {
                    i += 1;
                    col += 1;
                }
            }
            if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
                let save = i;
                let mut j = i + 1;
                if j < b.len() && (b[j] == b'+' || b[j] == b'-') {
                    j += 1;
                }
                if j < b.len() && b[j].is_ascii_digit() {
                    is_float = true;
                    i = j;
                    while i < b.len() && b[i].is_ascii_digit() {
                        i += 1;
                    }
                } else {
                    i = save;
                }
                col += (i - save) as u32;
            }

            if !is_float {
                let v = dec_i64(&b[start..i])
                    .ok_or_else(|| format!("line {}: integer literal out of range", sline))?;
                out.push(Token { tok: Tok::Int(v), line: sline, col: scol, start, end: i });
                continue;
            }
            let text: String =
                b[start..i].iter().filter(|ch| **ch != b'_').map(|ch| *ch as char).collect();
            let v: f64 = text
                .parse()
                .map_err(|_| format!("line {}: malformed float literal '{}'", sline, text))?;
            if !v.is_finite() {
                return Err(format!("line {}: float literal out of range", sline));
            }
            out.push(Token { tok: Tok::Float(v), line: sline, col: scol, start, end: i });
            continue;
        }

        if c == b'"' {
            i += 1;
            col += 1;
            let mut buf: Vec<u8> = Vec::with_capacity(24);
            loop {
                if i >= b.len() {
                    return Err(format!("line {}: unterminated string literal", sline));
                }
                let ch = b[i];
                if ch == b'"' {
                    i += 1;
                    col += 1;
                    break;
                }
                if ch == b'\\' {
                    if i + 1 >= b.len() {
                        return Err(format!("line {}: unterminated escape", line));
                    }
                    let e = b[i + 1];
                    if (b'0'..=b'7').contains(&e) {
                        let mut v: u32 = 0;
                        let mut n = 0usize;
                        while n < 3 && i + 1 + n < b.len() && (b'0'..=b'7').contains(&b[i + 1 + n]) {
                            v = v * 8 + (b[i + 1 + n] - b'0') as u32;
                            n += 1;
                        }
                        if v > 255 {
                            return Err(format!("line {}: octal escape is larger than a byte", line));
                        }
                        buf.push(v as u8);
                        i += 1 + n;
                        col += (1 + n) as u32;
                        continue;
                    }
                    let rep: u8 = match e {
                        b'n' => b'\n',
                        b't' => b'\t',
                        b'r' => b'\r',
                        b'\\' => b'\\',
                        b'"' => b'"',
                        b'\'' => b'\'',
                        _ => {
                            return Err(format!(
                                "line {}: unknown escape '\\{}'",
                                line, e as char
                            ))
                        }
                    };
                    buf.push(rep);
                    i += 2;
                    col += 2;
                    continue;
                }
                if ch == b'\n' {
                    return Err(format!("line {}: newline inside string literal", line));
                }
                buf.push(ch);
                i += 1;
                col += 1;
            }
            let s = String::from_utf8(buf)
                .map_err(|_| format!("line {}: string literal is not valid UTF-8", sline))?;
            out.push(Token { tok: Tok::Str(s), line: sline, col: scol, start, end: i });
            continue;
        }

        match sym_at(b, i) {
            Some((s, len)) => {
                out.push(Token { tok: Tok::Sym(s), line: sline, col: scol, start: i, end: i + len });
                i += len;
                col += len as u32;
            }
            None => {
                return Err(format!("line {}: unexpected character '{}'", sline, c as char));
            }
        }
    }

    out.push(Token { tok: Tok::Eof, line, col, start: i, end: i });
    Ok(out)
}
