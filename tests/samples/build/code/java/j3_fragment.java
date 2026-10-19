        double sum = 0;
        for (double p : prices) {
            if (p > 0) {
                sum += p;
            }
        }
        System.out.println("Total " + sum);
        return sum;