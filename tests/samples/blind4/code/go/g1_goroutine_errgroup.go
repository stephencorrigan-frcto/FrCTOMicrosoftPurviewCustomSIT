g, ctx := errgroup.WithContext(ctx)
g.Go(func() error { return fetch(ctx) })
if err := g.Wait(); err != nil { return err }