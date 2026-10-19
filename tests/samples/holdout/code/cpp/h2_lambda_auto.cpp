auto expensive = std::count_if(prices.begin(), prices.end(), [](double p) { return p > 100.0; });
std::cout << expensive << std::endl;