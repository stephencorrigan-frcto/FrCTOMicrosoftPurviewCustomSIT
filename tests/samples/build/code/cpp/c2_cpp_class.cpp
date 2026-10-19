#include <iostream>
#include <vector>

class Book {
public:
    void add(double p) { prices_.push_back(p); }
private:
    std::vector<double> prices_;
};