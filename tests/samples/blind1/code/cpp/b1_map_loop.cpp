std::map<std::string, double> prices{{"AAPL", 189.5}};
for (const auto& [sym, px] : prices) {
    std::cout << sym << " " << px << '\n';
}