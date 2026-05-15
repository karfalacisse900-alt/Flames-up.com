fn main() {
    cc::Build::new()
        .cpp(true)
        .file("cpp/flames_core.cpp")
        .include("cpp")
        .flag_if_supported("-std=c++17")
        .compile("flames_cpp_core");

    println!("cargo:rerun-if-changed=cpp/flames_core.cpp");
    println!("cargo:rerun-if-changed=cpp/flames_core.h");
}
