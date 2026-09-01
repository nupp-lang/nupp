use std::collections::BTreeSet;
use std::fs;
use std::io;
use std::path::Path;

pub const MAX_WALK_DEPTH: usize = 512;

#[derive(Debug)]
struct Pattern<'a> {
    components: Vec<&'a str>,
    root: &'a str,
}

pub fn expand(pattern: &str) -> io::Result<Vec<String>> {
    let pattern = parse(pattern)?;
    let mut matches = BTreeSet::new();
    let mut prefix = pattern.root.to_owned();
    descend(&pattern, &mut prefix, 0, MAX_WALK_DEPTH, &mut matches)?;
    Ok(matches.into_iter().collect())
}

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}

fn parse(text: &str) -> io::Result<Pattern<'_>> {
    let (root, tail) = root(text);
    let mut components = Vec::new();
    for component in tail.split('/') {
        if component.is_empty() {
            continue;
        }
        check_component(component)?;
        components.push(component);
    }
    if components.is_empty() && root.is_empty() {
        return Err(invalid("the pattern names no path"));
    }
    Ok(Pattern { components, root })
}

fn root(text: &str) -> (&str, &str) {
    let bytes = text.as_bytes();
    if cfg!(windows)
        && bytes.len() >= 3
        && bytes[1] == b':'
        && bytes[2] == b'/'
        && bytes[0].is_ascii_alphabetic()
    {
        (&text[..3], &text[3..])
    } else if let Some(tail) = text.strip_prefix('/') {
        ("/", tail)
    } else {
        ("", text)
    }
}

fn check_component(component: &str) -> io::Result<()> {
    let bytes = component.as_bytes();
    let mut at = 0;
    while at < bytes.len() {
        if bytes[at] == b'[' {
            let Some(end) = class_end(bytes, at + 1) else {
                return Err(invalid("the pattern has an unclosed ["));
            };
            at = end + 1;
            continue;
        }
        if bytes[at] == b'*' && at + 1 < bytes.len() && bytes[at + 1] == b'*' && bytes.len() != 2 {
            return Err(invalid(
                "a recursive wildcard must be a whole path component",
            ));
        }
        at += 1;
    }
    Ok(())
}

fn class_end(pattern: &[u8], mut at: usize) -> Option<usize> {
    if at == pattern.len() {
        return None;
    }
    if matches!(pattern[at], b'!' | b'^') {
        at += 1;
    }
    if at < pattern.len() && pattern[at] == b']' {
        at += 1;
    }
    while at < pattern.len() && pattern[at] != b']' {
        at += 1;
    }
    (at < pattern.len()).then_some(at)
}

fn class_accepts(pattern: &[u8], mut at: usize, end: usize, candidate: u8) -> bool {
    let mut negated = false;
    let mut found = false;
    if at != end && matches!(pattern[at], b'!' | b'^') {
        negated = true;
        at += 1;
    }
    while at != end {
        let low = pattern[at];
        at += 1;
        if at != end && at + 1 != end && pattern[at] == b'-' {
            let high = pattern[at + 1];
            at += 2;
            if (low..=high).contains(&candidate) {
                found = true;
            }
        } else if low == candidate {
            found = true;
        }
    }
    if negated { !found } else { found }
}

fn matches_name(pattern: &str, name: &str) -> bool {
    let pattern = pattern.as_bytes();
    let name = name.as_bytes();
    let mut pattern_at = 0;
    let mut name_at = 0;
    let mut star_at = None;
    let mut star_name = 0;

    while name_at < name.len() {
        if pattern_at < pattern.len() {
            match pattern[pattern_at] {
                b'*' => {
                    star_at = Some(pattern_at);
                    pattern_at += 1;
                    star_name = name_at;
                    continue;
                }
                b'?' => {
                    pattern_at += 1;
                    name_at += 1;
                    continue;
                }
                b'[' => {
                    if let Some(end) = class_end(pattern, pattern_at + 1) {
                        if class_accepts(pattern, pattern_at + 1, end, name[name_at]) {
                            pattern_at = end + 1;
                            name_at += 1;
                            continue;
                        }
                    }
                }
                literal if literal == name[name_at] => {
                    pattern_at += 1;
                    name_at += 1;
                    continue;
                }
                _ => {}
            }
        }
        let Some(star) = star_at else {
            return false;
        };
        star_name += 1;
        pattern_at = star + 1;
        name_at = star_name;
    }
    while pattern_at < pattern.len() && pattern[pattern_at] == b'*' {
        pattern_at += 1;
    }
    pattern_at == pattern.len()
}

fn has_wildcard(component: &str) -> bool {
    component
        .as_bytes()
        .iter()
        .any(|byte| matches!(byte, b'*' | b'?' | b'['))
}

fn descend(
    pattern: &Pattern<'_>,
    prefix: &mut String,
    component: usize,
    depth: usize,
    matches: &mut BTreeSet<String>,
) -> io::Result<()> {
    if component == pattern.components.len() {
        if !prefix.is_empty() && fs::symlink_metadata(opening(prefix)).is_ok() {
            matches.insert(prefix.clone());
        }
        return Ok(());
    }

    let text = pattern.components[component];
    if text == "**" {
        return recurse(pattern, prefix, component, depth, matches);
    }
    if !has_wildcard(text) {
        return with_child(pattern, prefix, text, component + 1, depth, matches);
    }

    let entries = match fs::read_dir(opening(prefix)) {
        Ok(entries) => entries,
        // The existing provider treats an unreadable branch as having no
        // matches rather than failing an otherwise useful recursive query.
        Err(_) => return Ok(()),
    };
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name().into_string().map_err(|_| {
            io::Error::new(io::ErrorKind::InvalidData, "glob entry is not valid UTF-8")
        })?;
        if matches_name(text, &name) {
            with_child(pattern, prefix, &name, component + 1, depth, matches)?;
        }
    }
    Ok(())
}

fn recurse(
    pattern: &Pattern<'_>,
    prefix: &mut String,
    component: usize,
    depth: usize,
    matches: &mut BTreeSet<String>,
) -> io::Result<()> {
    if depth == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("the directory tree is deeper than {MAX_WALK_DEPTH} levels"),
        ));
    }

    descend(pattern, prefix, component + 1, depth, matches)?;
    let entries = match fs::read_dir(opening(prefix)) {
        Ok(entries) => entries,
        Err(_) => return Ok(()),
    };
    for entry in entries {
        let entry = entry?;
        if !entry.file_type()?.is_dir() {
            continue;
        }
        let name = entry.file_name().into_string().map_err(|_| {
            io::Error::new(io::ErrorKind::InvalidData, "glob entry is not valid UTF-8")
        })?;
        let restore = prefix.len();
        push_component(prefix, &name);
        recurse(pattern, prefix, component, depth - 1, matches)?;
        prefix.truncate(restore);
    }
    Ok(())
}

fn with_child(
    pattern: &Pattern<'_>,
    prefix: &mut String,
    name: &str,
    component: usize,
    depth: usize,
    matches: &mut BTreeSet<String>,
) -> io::Result<()> {
    let restore = prefix.len();
    push_component(prefix, name);
    let answer = descend(pattern, prefix, component, depth, matches);
    prefix.truncate(restore);
    answer
}

fn push_component(prefix: &mut String, name: &str) {
    if !prefix.is_empty() && !prefix.ends_with('/') {
        prefix.push('/');
    }
    prefix.push_str(name);
}

fn opening(prefix: &str) -> &Path {
    if prefix.is_empty() {
        Path::new(".")
    } else {
        Path::new(prefix)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn root(name: &str) -> std::path::PathBuf {
        let mut random = [0u8; 8];
        getrandom::fill(&mut random).unwrap();
        let path = std::env::temp_dir().join(format!(
            "nupp-files-glob-{name}-{:016x}",
            u64::from_le_bytes(random)
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn grammar_is_explicit_and_bytewise() {
        assert!(matches_name("a?c", "abc"));
        assert!(matches_name("[!a]bc", "xbc"));
        assert!(matches_name("[a-c]x", "bx"));
        assert!(!matches_name("[!a]bc", "abc"));
        assert!(parse("root/**/file?.nupp").is_ok());
        assert!(parse("root/a**b").is_err());
        assert!(parse("root/[").is_err());
    }

    #[test]
    fn recursive_matches_are_sorted_and_unique() {
        let root = root("recursive");
        fs::create_dir_all(root.join("nested/deep")).unwrap();
        fs::write(root.join("root.nupp"), b"root").unwrap();
        fs::write(root.join("nested/child.nupp"), b"child").unwrap();
        fs::write(root.join("nested/deep/leaf.nupp"), b"leaf").unwrap();
        let pattern = format!("{}/**/**/[a-z]*.nupp", root.display());
        let found = expand(&pattern).unwrap();
        assert_eq!(found.len(), 3);
        assert!(found.windows(2).all(|pair| pair[0] < pair[1]));
        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn recursive_walk_does_not_follow_directory_symlinks() {
        use std::os::unix::fs::symlink;
        let root = root("symlink");
        fs::create_dir_all(root.join("real")).unwrap();
        fs::write(root.join("real/file.txt"), b"x").unwrap();
        symlink(&root, root.join("real/loop")).unwrap();
        let pattern = format!("{}/**/*.txt", root.display());
        assert_eq!(expand(&pattern).unwrap().len(), 1);
        fs::remove_dir_all(root).unwrap();
    }
}
