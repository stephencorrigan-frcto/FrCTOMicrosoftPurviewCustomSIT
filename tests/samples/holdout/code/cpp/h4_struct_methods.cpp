struct Quote {
    std::string symbol;
    double bid, ask;
    double mid() const { return (bid + ask) / 2.0; }
};