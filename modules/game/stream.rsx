fn stream_seed(master: u64, tag: u64) -> u64 {
    var z: u64 = master ^ (tag * 6364136223846793005 + 1442695040888963407);
    z = z ^ (z >> 33);
    z = z * 2147483647;
    z = z ^ (z >> 29);
    z = z * 424242423;
    z = z ^ (z >> 27);
    return z;
}

fn stream(master: u64, tag: u64) -> Rng {
    var r: Rng = zero(Rng);
    rand_seed(&mut r, stream_seed(master, tag));
    return r;
}
