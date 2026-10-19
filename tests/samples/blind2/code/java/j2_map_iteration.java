Map<String, Integer> counts = new TreeMap<>();
for (Map.Entry<String, Integer> e : counts.entrySet()) {
    System.out.printf("%s=%d%n", e.getKey(), e.getValue());
}