int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s file\n", argv[0]); return 1; }
    return process(argv[1]);
}