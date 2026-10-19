try {
    feed.connect();
} catch (const std::exception& e) {
    std::cerr << e.what() << '\n';
}