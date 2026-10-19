select {
case p := <-prices:
	handle(p)
case <-time.After(5 * time.Second):
	log.Println("timeout")
}