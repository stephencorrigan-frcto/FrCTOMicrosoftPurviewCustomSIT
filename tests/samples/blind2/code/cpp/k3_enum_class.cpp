enum class Side { Buy, Sell };
Side flip(Side s) { return s == Side::Buy ? Side::Sell : Side::Buy; }