ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
defer cancel()
resp, err := client.Do(req.WithContext(ctx))