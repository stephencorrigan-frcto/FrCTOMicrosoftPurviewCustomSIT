package com.example.pricing;

import java.util.ArrayList;
import java.util.List;

public class PriceBook {
    private final List<Double> prices = new ArrayList<>();

    public void add(double price) {
        if (price > 0) {
            prices.add(price);
        }
    }

    public double total() {
        double sum = 0;
        for (double p : prices) {
            sum += p;
        }
        return sum;
    }
}