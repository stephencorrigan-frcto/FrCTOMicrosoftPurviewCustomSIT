package com.contoso.pricing;

import java.util.ArrayList;
import java.util.List;

public class PriceBook {
    private final List<Double> prices = new ArrayList<>();

    @Override
    public String toString() {
        return "PriceBook(" + prices.size() + ")";
    }
}