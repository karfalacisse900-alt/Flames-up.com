use std::ffi::CStr;
use std::os::raw::c_char;
use std::slice;

#[no_mangle]
pub extern "C" fn mira_rust_hash_bytes(bytes: *const u8, length: usize) -> u64 {
    if bytes.is_null() || length == 0 {
        return 0;
    }

    let data = unsafe { slice::from_raw_parts(bytes, length) };
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in data {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

#[no_mangle]
pub extern "C" fn mira_rust_link_risk_score(url: *const c_char) -> u32 {
    let value = read_c_string(url).to_ascii_lowercase();
    if value.is_empty() {
        return 0;
    }

    let mut risk = 0;
    if value.starts_with("javascript:")
        || value.starts_with("data:")
        || value.starts_with("file:")
        || value.starts_with("chrome:")
    {
        risk += 100;
    }
    if !(value.starts_with("https://") || value.starts_with("http://")) {
        risk += 40;
    }
    if value.contains("@") || value.contains("%00") || value.contains("xn--") {
        risk += 20;
    }
    if value.len() > 300 {
        risk += 15;
    }
    risk.min(100)
}

#[no_mangle]
pub extern "C" fn mira_rust_text_spam_score(text: *const c_char) -> u32 {
    let value = read_c_string(text).to_ascii_lowercase();
    if value.is_empty() {
        return 0;
    }

    let link_count = value.matches("http://").count() + value.matches("https://").count();
    let tag_count = value.matches('#').count() + value.matches('@').count();
    let repeated_bang = value.matches("!!!").count();
    let repeated_money = value.matches("$$").count();

    let mut score = 0;
    score += (link_count as u32).saturating_mul(18);
    score += (tag_count as u32).saturating_mul(4).min(24);
    score += (repeated_bang as u32).saturating_mul(8);
    score += (repeated_money as u32).saturating_mul(12);

    if value.contains("free money") || value.contains("crypto giveaway") || value.contains("click now") {
        score += 30;
    }
    score.min(100)
}

fn read_c_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }.to_string_lossy().trim().to_string()
}
