use crate::{hash_tagged, Hash256};

pub(crate) fn root(leaves: &[Hash256]) -> Hash256 {
    if leaves.is_empty() {
        return hash_tagged("merkle/empty/v1", &[]);
    }

    let mut level: Vec<Hash256> = leaves
        .iter()
        .map(|leaf| hash_tagged("merkle/leaf/v1", &[leaf.as_bytes()]))
        .collect();
    while level.len() > 1 {
        let mut next = Vec::with_capacity(level.len().div_ceil(2));
        for pair in level.chunks(2) {
            let left = pair[0];
            let right = pair.get(1).copied().unwrap_or(left);
            next.push(hash_tagged(
                "merkle/node/v1",
                &[left.as_bytes(), right.as_bytes()],
            ));
        }
        level = next;
    }
    level[0]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordering_changes_root() {
        let one = hash_tagged("test", &[b"one"]);
        let two = hash_tagged("test", &[b"two"]);
        assert_ne!(root(&[one, two]), root(&[two, one]));
        assert_eq!(root(&[one, two]), root(&[one, two]));
    }
}
