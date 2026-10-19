ch := make(chan int)
go func() { ch <- compute() }()
result := <-ch