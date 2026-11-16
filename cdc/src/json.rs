#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    pub fn parse(src: &str) -> Result<Value, String> {
        let mut p = Parser { b: src.as_bytes(), i: 0 };
        p.ws();
        let v = p.value()?;
        p.ws();
        if p.i != p.b.len() {
            return p.err("trailing characters");
        }
        Ok(v)
    }

    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(kv) => kv.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_object(&self) -> Option<&[(String, Value)]> {
        match self {
            Value::Object(kv) => Some(kv),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Value::Int(n) => Some(*n),
            _ => None,
        }
    }

    pub fn to_pretty(&self) -> String {
        let mut out = String::new();
        self.write(&mut out, 0);
        out
    }

    fn write(&self, out: &mut String, depth: usize) {
        match self {
            Value::Null => out.push_str("null"),
            Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Value::Int(n) => out.push_str(&n.to_string()),
            Value::Float(f) => {
                if f.is_finite() {
                    out.push_str(&f.to_string());
                } else {
                    out.push_str("null");
                }
            }
            Value::Str(s) => write_str(out, s),
            Value::Array(items) => {
                if items.is_empty() {
                    out.push_str("[]");
                    return;
                }
                out.push_str("[\n");
                for (i, v) in items.iter().enumerate() {
                    indent(out, depth + 1);
                    v.write(out, depth + 1);
                    if i + 1 < items.len() {
                        out.push(',');
                    }
                    out.push('\n');
                }
                indent(out, depth);
                out.push(']');
            }
            Value::Object(kv) => {
                if kv.is_empty() {
                    out.push_str("{}");
                    return;
                }
                out.push_str("{\n");
                for (i, (k, v)) in kv.iter().enumerate() {
                    indent(out, depth + 1);
                    write_str(out, k);
                    out.push_str(": ");
                    v.write(out, depth + 1);
                    if i + 1 < kv.len() {
                        out.push(',');
                    }
                    out.push('\n');
                }
                indent(out, depth);
                out.push('}');
            }
        }
    }
}

fn indent(out: &mut String, depth: usize) {
    for _ in 0..depth {
        out.push_str("  ");
    }
}

fn write_str(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<u8> {
        self.b.get(self.i).copied()
    }

    fn bump(&mut self) -> Option<u8> {
        let c = self.peek();
        if c.is_some() {
            self.i += 1;
        }
        c
    }

    fn ws(&mut self) {
        while let Some(c) = self.peek() {
            match c {
                b' ' | b'\t' | b'\n' | b'\r' => self.i += 1,
                _ => break,
            }
        }
    }

    fn err<T>(&self, m: &str) -> Result<T, String> {
        Err(format!("json: {} at byte {}", m, self.i))
    }

    fn value(&mut self) -> Result<Value, String> {
        match self.peek() {
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => self.string().map(Value::Str),
            Some(b't') => self.literal("true", Value::Bool(true)),
            Some(b'f') => self.literal("false", Value::Bool(false)),
            Some(b'n') => self.literal("null", Value::Null),
            Some(c) if c == b'-' || c.is_ascii_digit() => self.number(),
            Some(_) => self.err("unexpected character"),
            None => self.err("unexpected end of input"),
        }
    }

    fn literal(&mut self, word: &str, v: Value) -> Result<Value, String> {
        if self.b[self.i..].starts_with(word.as_bytes()) {
            self.i += word.len();
            Ok(v)
        } else {
            self.err("bad literal")
        }
    }

    fn object(&mut self) -> Result<Value, String> {
        self.bump();
        let mut kv = Vec::new();
        self.ws();
        if self.peek() == Some(b'}') {
            self.bump();
            return Ok(Value::Object(kv));
        }
        loop {
            self.ws();
            if self.peek() != Some(b'"') {
                return self.err("expected a key");
            }
            let k = self.string()?;
            self.ws();
            if self.bump() != Some(b':') {
                return self.err("expected ':'");
            }
            self.ws();
            let v = self.value()?;
            kv.push((k, v));
            self.ws();
            match self.bump() {
                Some(b',') => continue,
                Some(b'}') => return Ok(Value::Object(kv)),
                _ => return self.err("expected ',' or '}'"),
            }
        }
    }

    fn array(&mut self) -> Result<Value, String> {
        self.bump();
        let mut items = Vec::new();
        self.ws();
        if self.peek() == Some(b']') {
            self.bump();
            return Ok(Value::Array(items));
        }
        loop {
            self.ws();
            items.push(self.value()?);
            self.ws();
            match self.bump() {
                Some(b',') => continue,
                Some(b']') => return Ok(Value::Array(items)),
                _ => return self.err("expected ',' or ']'"),
            }
        }
    }

    fn string(&mut self) -> Result<String, String> {
        if self.bump() != Some(b'"') {
            return self.err("expected '\"'");
        }
        let mut s = String::new();
        loop {
            let c = match self.bump() {
                Some(c) => c,
                None => return self.err("unterminated string"),
            };
            match c {
                b'"' => return Ok(s),
                b'\\' => {
                    let e = match self.bump() {
                        Some(e) => e,
                        None => return self.err("unterminated escape"),
                    };
                    match e {
                        b'"' => s.push('"'),
                        b'\\' => s.push('\\'),
                        b'/' => s.push('/'),
                        b'b' => s.push('\u{8}'),
                        b'f' => s.push('\u{c}'),
                        b'n' => s.push('\n'),
                        b'r' => s.push('\r'),
                        b't' => s.push('\t'),
                        b'u' => {
                            let hi = self.hex4()?;
                            if (0xD800..0xDC00).contains(&hi) {
                                if self.bump() != Some(b'\\') || self.bump() != Some(b'u') {
                                    return self.err("unpaired surrogate");
                                }
                                let lo = self.hex4()?;
                                if !(0xDC00..0xE000).contains(&lo) {
                                    return self.err("bad low surrogate");
                                }
                                let cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
                                match char::from_u32(cp) {
                                    Some(ch) => s.push(ch),
                                    None => return self.err("bad code point"),
                                }
                            } else {
                                match char::from_u32(hi) {
                                    Some(ch) => s.push(ch),
                                    None => return self.err("bad code point"),
                                }
                            }
                        }
                        _ => return self.err("unknown escape"),
                    }
                }
                c if c < 0x20 => return self.err("control character in string"),
                c if c < 0x80 => s.push(c as char),
                _ => {
                    self.i -= 1;
                    let rest = match std::str::from_utf8(&self.b[self.i..]) {
                        Ok(r) => r,
                        Err(_) => return self.err("invalid utf-8"),
                    };
                    let ch = match rest.chars().next() {
                        Some(ch) => ch,
                        None => return self.err("invalid utf-8"),
                    };
                    s.push(ch);
                    self.i += ch.len_utf8();
                }
            }
        }
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let mut v = 0u32;
        for _ in 0..4 {
            let c = match self.bump() {
                Some(c) => c,
                None => return self.err("truncated escape"),
            };
            let d = match c {
                b'0'..=b'9' => (c - b'0') as u32,
                b'a'..=b'f' => (c - b'a' + 10) as u32,
                b'A'..=b'F' => (c - b'A' + 10) as u32,
                _ => return self.err("bad hex digit"),
            };
            v = (v << 4) | d;
        }
        Ok(v)
    }

    fn number(&mut self) -> Result<Value, String> {
        let start = self.i;
        let mut float = false;
        if self.peek() == Some(b'-') {
            self.i += 1;
        }
        while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
            self.i += 1;
        }
        if self.peek() == Some(b'.') {
            float = true;
            self.i += 1;
            while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
                self.i += 1;
            }
        }
        if matches!(self.peek(), Some(b'e') | Some(b'E')) {
            float = true;
            self.i += 1;
            if matches!(self.peek(), Some(b'+') | Some(b'-')) {
                self.i += 1;
            }
            while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
                self.i += 1;
            }
        }
        let text = std::str::from_utf8(&self.b[start..self.i]).unwrap_or("");
        if float {
            text.parse::<f64>()
                .map(Value::Float)
                .map_err(|_| format!("json: bad number '{}'", text))
        } else {
            text.parse::<i64>()
                .map(Value::Int)
                .map_err(|_| format!("json: bad number '{}'", text))
        }
    }
}
