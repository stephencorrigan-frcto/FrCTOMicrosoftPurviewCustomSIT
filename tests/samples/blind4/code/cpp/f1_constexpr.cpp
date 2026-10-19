constexpr double kFee = 0.0005;
inline double fee(double notional) { return notional * kFee; }