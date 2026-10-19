try (BufferedReader br = new BufferedReader(new FileReader(path))) {
    String line;
    while ((line = br.readLine()) != null) {
        rows.add(line);
    }
}