cargo clean
RUSTFLAGS="-C target-cpu=native" cargo build --release
./target/release/main
