Money operator+(const Money& a, const Money& b) {
    return Money(a.cents + b.cents);
}