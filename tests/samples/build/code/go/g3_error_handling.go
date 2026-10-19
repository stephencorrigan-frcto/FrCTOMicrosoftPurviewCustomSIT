f, err := os.Open(path)
if err != nil {
	return fmt.Errorf("open %s: %w", path, err)
}
defer f.Close()