class Order {
    int qty_;
public:
    explicit Order(int q) : qty_(q) {}
    int qty() const { return qty_; }
};