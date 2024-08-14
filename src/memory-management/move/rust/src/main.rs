fn main() {
    let mut some_numbers = vec![1, 2];
    let other = some_numbers.clone();
    some_numbers.push(3);
    println!("{:?}", other);
    println!("{:?}", some_numbers);
}
