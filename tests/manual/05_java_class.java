package com.contoso.test;

import java.util.ArrayList;
import java.util.List;

public class PriceBook {
    private final List<Double> prices = new ArrayList<>();

    public double total() {
        double sum = 0;
        for (double p : prices) {
            sum += p;
        }
        return sum;
    }
}