func TestTotal(t *testing.T) {
	b := &Book{Prices: []float64{1, 2}}
	if got := b.Total(); got != 3 {
		t.Errorf("got %v", got)
	}
}