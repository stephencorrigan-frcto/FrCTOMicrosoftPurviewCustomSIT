static int sum(int... xs) {
    int s = 0;
    for (int x : xs) s += x;
    return s;
}