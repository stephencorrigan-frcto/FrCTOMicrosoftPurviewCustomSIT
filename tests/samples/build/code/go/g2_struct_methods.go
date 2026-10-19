type Book struct {
	Prices []float64
}

func (b *Book) Total() float64 {
	sum := 0.0
	for _, p := range b.Prices {
		sum += p
	}
	return sum
}