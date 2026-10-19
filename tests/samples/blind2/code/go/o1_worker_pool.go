var wg sync.WaitGroup
for i := 0; i < 4; i++ {
	wg.Add(1)
	go worker(i, jobs, &wg)
}
wg.Wait()